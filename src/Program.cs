// CH510 Display - sends CPU temperature/usage to the DeepCool CH510 MESH DIGITAL front display.
// Protocol (from the open-source deepcool-digital-linux project): an ASCII line
// "HLXDATA(usage,temp,0,0,C)\r\n" written as a 65-byte HID output report (report ID 0).

using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using HidSharp;
using LibreHardwareMonitor.Hardware;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        bool fahrenheit = args.Any(a => a.Equals("--fahrenheit", StringComparison.OrdinalIgnoreCase));

        bool isFirstInstance;
        using (var mutex = new Mutex(true, @"Global\CH510Display", out isFirstInstance))
        {
            if (!isFirstInstance) return;
            Application.EnableVisualStyles();
            Application.Run(new TrayApp(fahrenheit));
        }
    }
}

sealed class TrayApp : ApplicationContext
{
    readonly bool fahrenheit;
    readonly CpuSensors cpu = new CpuSensors();
    readonly Ch510Device display = new Ch510Device();
    readonly NotifyIcon tray = new NotifyIcon();
    readonly ToolStripMenuItem statusItem = new ToolStripMenuItem("Starting...") { Enabled = false };
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer { Interval = 1000 };
    IntPtr iconHandle = IntPtr.Zero;
    string lastStatus;

    public TrayApp(bool fahrenheit)
    {
        this.fahrenheit = fahrenheit;

        var menu = new ContextMenuStrip();
        menu.Items.Add(statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, delegate { ExitThread(); });
        tray.ContextMenuStrip = menu;
        tray.Visible = true;
        SetIcon("..", "CH510 Display");

        timer.Tick += delegate { Tick(); };
        timer.Start();
        Tick();
    }

    void Tick()
    {
        float? temp, load;
        cpu.Read(out temp, out load);

        string unit = fahrenheit ? "F" : "C";
        if (temp == null)
        {
            SetStatus("CPU temperature unavailable - is the PawnIO driver installed?");
            SetIcon("--", "CH510 Display: CPU temperature unavailable");
            return;
        }

        int t = (int)Math.Round(fahrenheit ? temp.Value * 9 / 5 + 32 : temp.Value);
        int u = load == null ? 0 : (int)Math.Round(load.Value);
        bool sent = display.Send(u, t, unit);

        string text = string.Format("CPU {0}°{1}, {2}% load", t, unit, u);
        SetStatus(sent ? text : text + " - case display not found");
        SetIcon(t.ToString(), "CH510 Display: " + statusItem.Text);
    }

    void SetStatus(string status)
    {
        statusItem.Text = status;
        // Only log changes in state (connected / not found / unavailable), not every reading.
        string kind = status.Contains(" - ") ? status.Substring(status.IndexOf(" - ")) : "ok";
        if (kind != lastStatus) { Log.Write(status); lastStatus = kind; }
    }

    // Draws the temperature number as the tray icon.
    void SetIcon(string text, string tooltip)
    {
        using (var bmp = new Bitmap(16, 16))
        using (var g = Graphics.FromImage(bmp))
        using (var font = new Font("Segoe UI", text.Length > 2 ? 6.5f : 8.5f, FontStyle.Bold, GraphicsUnit.Point))
        {
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.FromArgb(20, 20, 20));
            var size = g.MeasureString(text, font);
            g.DrawString(text, font, Brushes.White, (16 - size.Width) / 2 + 0.5f, (16 - size.Height) / 2 + 0.5f);

            IntPtr newHandle = bmp.GetHicon();
            tray.Icon = Icon.FromHandle(newHandle);
            if (iconHandle != IntPtr.Zero) DestroyIcon(iconHandle);
            iconHandle = newHandle;
        }
        tray.Text = tooltip.Length > 63 ? tooltip.Substring(0, 63) : tooltip;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            timer.Dispose();
            tray.Visible = false;
            tray.Dispose();
            display.Dispose();
            cpu.Dispose();
            if (iconHandle != IntPtr.Zero) DestroyIcon(iconHandle);
        }
        base.Dispose(disposing);
    }

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr handle);
}

sealed class CpuSensors : IDisposable
{
    // Preferred temperature sensors, best first: Intel package, AMD control temp, hottest core.
    static readonly string[] TempNames = { "CPU Package", "Core (Tctl/Tdie)", "Core (Tctl)", "Core Max" };

    readonly Computer computer = new Computer { IsCpuEnabled = true };

    public CpuSensors()
    {
        computer.Open();
    }

    public void Read(out float? temp, out float? load)
    {
        temp = null;
        load = null;
        foreach (var hw in computer.Hardware.Where(h => h.HardwareType == HardwareType.Cpu))
        {
            hw.Update();
            var sensors = hw.Sensors.Concat(hw.SubHardware.SelectMany(s => { s.Update(); return s.Sensors; })).ToList();
            var temps = sensors.Where(s => s.SensorType == SensorType.Temperature && s.Value.HasValue && s.Value > 0).ToList();

            foreach (var name in TempNames)
            {
                var match = temps.FirstOrDefault(s => s.Name == name);
                if (match != null) { temp = match.Value; break; }
            }
            if (temp == null && temps.Count > 0) temp = temps.Max(s => s.Value);

            var total = sensors.FirstOrDefault(s => s.SensorType == SensorType.Load && s.Name == "CPU Total");
            if (total != null) load = total.Value;
            if (temp != null) return;
        }
    }

    public void Dispose()
    {
        computer.Close();
    }
}

sealed class Ch510Device : IDisposable
{
    const int VendorId = 0x34D3;
    const int ProductId = 0x1100;

    HidStream stream;

    // Returns false if the display isn't connected; reconnects automatically on later calls
    // (e.g. after sleep/resume or a USB re-plug).
    public bool Send(int usage, int temp, string unit)
    {
        try
        {
            if (stream == null)
            {
                var device = DeviceList.Local.GetHidDevices(VendorId, ProductId).FirstOrDefault();
                HidStream opened;
                if (device == null || !device.TryOpen(out opened)) return false;
                stream = opened;
                stream.WriteTimeout = 1000;
                Log.Write("Connected to CH510 display");
            }

            var report = new byte[stream.Device.GetMaxOutputReportLength()];
            var message = Encoding.ASCII.GetBytes(string.Format("HLXDATA({0},{1},0,0,{2})\r\n", usage, temp, unit));
            Array.Copy(message, 0, report, 1, Math.Min(message.Length, report.Length - 1)); // byte 0 = report ID 0
            stream.Write(report);
            return true;
        }
        catch (Exception ex)
        {
            Log.Write("Display write failed: " + ex.Message);
            Dispose();
            return false;
        }
    }

    public void Dispose()
    {
        if (stream != null) { stream.Dispose(); stream = null; }
    }
}

static class Log
{
    static readonly string LogPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "CH510Display.log");

    public static void Write(string line)
    {
        try
        {
            if (File.Exists(LogPath) && new FileInfo(LogPath).Length > 256 * 1024) File.Delete(LogPath);
            File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + Environment.NewLine);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}

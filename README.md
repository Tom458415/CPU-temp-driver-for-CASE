# CH510 Display

A small tray app that shows your CPU temperature on the DeepCool CH510 MESH DIGITAL front display, as a replacement for DeepCool's software. It updates once a second and starts automatically when you log in.

## Setup (once)

1. **Install the PawnIO driver.** The app needs it to read the real CPU temperature. Run this in a terminal and accept the prompt:
   ```
   winget install namazso.PawnIO
   ```
   or get the installer from https://pawnio.eu
2. **Close DeepCool's own software** and turn off its autostart. Two programs can't both drive the display.
3. **Build:** right-click `build.ps1` → *Run with PowerShell*. It downloads the libraries from nuget.org and compiles `bin\CH510Display.exe`. You don't need Visual Studio or the .NET SDK.
4. **Install:** right-click `install.ps1` → *Run with PowerShell*, then click **Yes** on the admin prompt.
   This copies the app to `C:\Program Files\CH510Display` and adds a Task Scheduler task called **CH510 Display** that starts it at every login with admin rights, so there's no UAC prompt at startup.

The tray icon shows the current temperature. Hover over it for details, or right-click → **Exit** to close it.

## Options

- Fahrenheit: in Task Scheduler, edit the *CH510 Display* task → Actions → add `--fahrenheit` as an argument.
- Uninstall: right-click `uninstall.ps1` → *Run with PowerShell*.

## Troubleshooting

- **Tray shows `--`**: the CPU temperature can't be read. Check that PawnIO is installed, then reboot.
- **"case display not found"**: check that the case's internal USB cable is plugged into a motherboard USB 2.0 header. Windows lists the display as a "HID-compliant bar code badge reader" (USB ID `34D3:1100`).
- The log is at `C:\Program Files\CH510Display\CH510Display.log`.

## Rebuilding

Run `build.ps1`. It uses the C# compiler that comes with Windows (.NET Framework 4.8). On the first build, `restore-libs.ps1` downloads LibreHardwareMonitorLib 0.9.6, HidSharp and their dependencies from nuget.org into `lib\`.

The display protocol comes from the open-source [deepcool-digital-linux](https://github.com/Nortank12/deepcool-digital-linux) project.

# Builds bin\CH510Display.exe with the C# compiler that ships with Windows (.NET Framework 4.8).
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$lib  = Join-Path $root 'lib'
$bin  = Join-Path $root 'bin'
$fx   = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"

if (-not (Test-Path "$lib\LibreHardwareMonitorLib.dll")) { & "$root\restore-libs.ps1" -Out $lib }

New-Item -ItemType Directory -Force $bin | Out-Null
Copy-Item "$lib\*.dll" $bin -Force

& "$fx\csc.exe" /nologo /target:winexe /platform:x64 /optimize+ `
    /out:"$bin\CH510Display.exe" /win32manifest:"$root\src\app.manifest" `
    /reference:"$lib\LibreHardwareMonitorLib.dll" /reference:"$lib\HidSharp.dll" `
    /reference:"$fx\netstandard.dll" `
    /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
    "$root\src\Program.cs"
if ($LASTEXITCODE -ne 0) { throw "Compile failed" }

# The NuGet libraries were built against slightly different versions of each other,
# so redirect every reference to the version actually shipped in bin\.
$redirects = foreach ($dll in Get-ChildItem "$lib\*.dll") {
    $name = [Reflection.AssemblyName]::GetAssemblyName($dll.FullName)
    $token = ($name.GetPublicKeyToken() | ForEach-Object { $_.ToString('x2') }) -join ''
    if (-not $token) { continue }
    @"
      <dependentAssembly>
        <assemblyIdentity name="$($name.Name)" publicKeyToken="$token" culture="neutral" />
        <bindingRedirect oldVersion="0.0.0.0-$($name.Version)" newVersion="$($name.Version)" />
      </dependentAssembly>
"@
}
@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup>
  <runtime>
    <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
$($redirects -join "`n")
    </assemblyBinding>
  </runtime>
</configuration>
"@ | Set-Content -Encoding utf8 "$bin\CH510Display.exe.config"

"Built $bin\CH510Display.exe"

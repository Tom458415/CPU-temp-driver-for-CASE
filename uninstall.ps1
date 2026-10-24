# Removes the CH510 Display startup task and installed files.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

Stop-ScheduledTask -TaskName 'CH510 Display' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'CH510 Display' -Confirm:$false -ErrorAction SilentlyContinue
Get-Process CH510Display -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
Remove-Item -Recurse -Force (Join-Path $env:ProgramFiles 'CH510Display') -ErrorAction SilentlyContinue
"CH510 Display removed."
Read-Host 'Press Enter to close'

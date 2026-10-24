# Installs CH510 Display to Program Files and starts it automatically (as admin) at every login.
# Run from a normal PowerShell window: it asks for admin rights itself.
param([string]$User = "$env:USERDOMAIN\$env:USERNAME")
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -User `"$User`""
    return
}

$src  = Join-Path $PSScriptRoot 'bin'
$dest = Join-Path $env:ProgramFiles 'CH510Display'
$task = 'CH510 Display'

if (-not (Test-Path "$src\CH510Display.exe")) { throw "Build first: run build.ps1" }

# Installed under Program Files (admin-only writable) because the task runs with admin rights.
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Get-Process CH510Display -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item "$src\*" $dest -Recurse -Force

$action    = New-ScheduledTaskAction -Execute "$dest\CH510Display.exe" -WorkingDirectory $dest
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $User
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries `
                 -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Shows CPU temperature on the DeepCool CH510 MESH DIGITAL case display.' -Force | Out-Null
Start-ScheduledTask -TaskName $task

if (-not (Get-Service PawnIO -ErrorAction SilentlyContinue)) {
    Write-Warning "PawnIO driver not found. CPU temperature will show '--' until you install it: winget install namazso.PawnIO"
}
"Installed to $dest and started. It will start automatically at every login."
Read-Host 'Press Enter to close'

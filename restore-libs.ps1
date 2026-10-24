# Downloads LibreHardwareMonitorLib and its .NET Framework dependencies from nuget.org into lib\.
param([string]$Out = (Join-Path $PSScriptRoot 'lib'), [string]$Root = 'LibreHardwareMonitorLib', [string]$RootVersion = '0.9.6')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$cache = Join-Path $env:TEMP "ch510-nuget-$(Get-Random)"
New-Item -ItemType Directory -Force $cache, $Out | Out-Null
$seen = @{}
$queue = New-Object System.Collections.Queue
$queue.Enqueue(@($Root, $RootVersion))

function Pick-Folder($names, $prefs) { foreach ($p in $prefs) { if ($names -contains $p) { return $p } }; return $null }
$tfmPrefs = 'net472','net471','net47','net462','net461','net46','net45','netstandard2.0'
$grpPrefs = '.NETFramework4.7.2','.NETFramework4.6.2','.NETFramework4.6.1','.NETFramework4.6','.NETFramework4.5','.NETStandard2.0'

while ($queue.Count -gt 0) {
    $id, $ver = $queue.Dequeue()
    $ver = ($ver -replace '[\[\]\(\)]', '').Split(',')[0].Trim()
    $key = $id.ToLower()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $ver
    $pkg = Join-Path $cache "$key.$ver.nupkg"
    Invoke-WebRequest -UseBasicParsing "https://api.nuget.org/v3-flatcontainer/$key/$ver/$key.$ver.nupkg" -OutFile $pkg
    $dir = Join-Path $cache "$key.$ver"
    [IO.Compression.ZipFile]::ExtractToDirectory($pkg, $dir)

    [xml]$spec = Get-Content (Get-ChildItem $dir -Filter *.nuspec | Select-Object -First 1).FullName
    $groups = @($spec.package.metadata.dependencies.group)
    $g = $null
    $gname = Pick-Folder ($groups | ForEach-Object { $_.targetFramework }) $grpPrefs
    if ($gname) { $g = $groups | Where-Object { $_.targetFramework -eq $gname } }
    if ($g) { foreach ($d in @($g.dependency)) { if ($d) { $queue.Enqueue(@($d.id, $d.version)) } } }

    # Most packages ship lib\<tfm>; LibreHardwareMonitorLib ships runtimes\win-x64\lib\<tfm>.
    $picked = '-'
    foreach ($lib in (Join-Path $dir 'runtimes\win-x64\lib'), (Join-Path $dir 'lib')) {
        if (-not (Test-Path $lib)) { continue }
        $tfm = Pick-Folder (Get-ChildItem $lib -Directory | ForEach-Object { $_.Name }) $tfmPrefs
        if ($tfm) {
            Get-ChildItem (Join-Path $lib $tfm) -Filter *.dll | Copy-Item -Destination $Out -Force
            $picked = $tfm
            break
        }
    }
    "{0} {1}  [{2}]" -f $id, $ver, $picked
}
Remove-Item -Recurse -Force $cache

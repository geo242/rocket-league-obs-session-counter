<#
.SYNOPSIS
  Turns on Rocket League's Stats API, which the overlay reads match results from.

.DESCRIPTION
  Finds Rocket League (Epic Games and Steam installs) and sets PacketSendRate in
  TAGame\Config\DefaultStatsAPI.ini to a value above 0. Installs that already have it on
  are left alone. Changing a file under Program Files needs admin, so the script asks
  for it only when there's something to change.

    powershell -ExecutionPolicy Bypass -File .\enable-stats-api.ps1

  Restart Rocket League afterwards. A big game update can reset the file; just run this again.

.PARAMETER Path
  Rocket League install folder(s) to use instead of searching, e.g. 'D:\Games\rocketleague'.

.PARAMETER Rate
  Updates per second the game sends (1-120). Default 20.
#>
param(
    [string[]]$Path,
    [ValidateRange(1, 120)][int]$Rate = 20
)

$ErrorActionPreference = 'Stop'

function Find-Installs {
    $found = @()
    # Epic Games launcher manifests
    $manifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path $manifests) {
        foreach ($m in Get-ChildItem $manifests -Filter '*.item') {
            try {
                $j = Get-Content $m.FullName -Raw | ConvertFrom-Json
                if ($j.DisplayName -match 'Rocket League' -and $j.InstallLocation) { $found += $j.InstallLocation }
            } catch {}
        }
    }
    # Steam libraries
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $libs = @($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $libs += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
        }
        foreach ($lib in $libs | Select-Object -Unique) {
            $rl = Join-Path $lib 'steamapps\common\rocketleague'
            if (Test-Path $rl) { $found += $rl }
        }
    }
    # Windows paths are case-insensitive; Steam reports the same folder in different cases
    $seen = @{}
    foreach ($f in $found) {
        $p = (Resolve-Path $f).Path.TrimEnd('\')
        if (-not $seen.ContainsKey($p.ToLowerInvariant())) { $seen[$p.ToLowerInvariant()] = $true; $p }
    }
}

$installs = if ($Path) { @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) } else { @(Find-Installs) }
if (-not $installs) {
    Write-Host 'Rocket League not found. Run again with -Path "<your Rocket League folder>".'
    exit 1
}

$needsChange = @()
foreach ($dir in $installs) {
    $ini = Join-Path $dir 'TAGame\Config\DefaultStatsAPI.ini'
    if (-not (Test-Path $ini)) { Write-Host "No DefaultStatsAPI.ini in $dir (is that a Rocket League folder?)"; continue }
    $text = Get-Content $ini -Raw
    $m = [regex]::Match($text, '(?m)^\s*PacketSendRate\s*=\s*(\d+)')
    if ($m.Success -and [int]$m.Groups[1].Value -gt 0) {
        Write-Host "Already on ($($m.Groups[1].Value) updates/s): $ini"
    } else {
        $needsChange += $ini
    }
}
if (-not $needsChange) { exit 0 }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
foreach ($ini in $needsChange) {
    try {
        $text = Get-Content $ini -Raw
        if ($text -match '(?m)^\s*PacketSendRate\s*=') {
            $text = [regex]::Replace($text, '(?m)^(\s*PacketSendRate\s*=\s*)\d*', "`${1}$Rate")
        } else {
            $text = $text.TrimEnd() + "`r`nPacketSendRate=$Rate`r`n"
        }
        Copy-Item $ini "$ini.bak" -Force
        [IO.File]::WriteAllText($ini, $text)
        Write-Host "Turned on ($Rate updates/s): $ini"
    } catch [UnauthorizedAccessException] {
        if ($admin) { throw }
        Write-Host 'Needs admin to change files in Program Files; asking now...'
        $dirs = ($needsChange | ForEach-Object { Split-Path (Split-Path (Split-Path $_)) }) -join ','
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Rate', $Rate, '-Path', "`"$dirs`"")
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
        exit 0
    }
}
Write-Host 'Restart Rocket League for the change to take effect.'

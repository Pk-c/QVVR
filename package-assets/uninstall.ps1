#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$GameDir=$PSScriptRoot,[switch]$RemoveConfig,[switch]$Interactive)
$ErrorActionPreference='Stop'

function Get-QvvrSafePcPath([string]$Root,[string]$Relative) {
    if ($Relative -match '(^|[\\/])\.\.?([\\/]|$)' -or [IO.Path]::IsPathRooted($Relative)) { throw 'Unsafe relative path.' }
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (!$path.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped the game directory.' }
    $current=$path
    while ($current.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a linked/junction path. No files were removed.' }
        }
        if ($current -eq $base) { break }
        $current=Split-Path -Parent $current
    }
    return $path
}

function Assert-QvvrPcClosed {
    if (Get-Process -Name QV -ErrorAction SilentlyContinue) { throw 'QV is running. Close it yourself and retry. No process was terminated.' }
}

function Invoke-QvvrPcUninstall {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$GameDir,[switch]$RemoveConfig,[switch]$Interactive)
    $root=(Resolve-Path -LiteralPath $GameDir).ProviderPath
    $exe=Get-QvvrSafePcPath $root 'QV.exe'
    if (!(Test-Path -LiteralPath $exe -PathType Leaf) -or !(Test-Path -LiteralPath (Get-QvvrSafePcPath $root 'QV_Data') -PathType Container)) { throw 'This is not a QV game directory (QV.exe / QV_Data missing).' }
    Assert-QvvrPcClosed
    $plugin=Get-QvvrSafePcPath $root 'BepInEx/plugins/QVVR'
    $config=Get-QvvrSafePcPath $root 'BepInEx/config/dev.qvvr.prototype.cfg'
    $hasPlugin=Test-Path -LiteralPath $plugin -PathType Container
    if (!$hasPlugin -and !($RemoveConfig -and (Test-Path -LiteralPath $config -PathType Leaf))) { Write-Host 'QVVR is already uninstalled. Nothing changed.'; return }
    if ($hasPlugin) {
        if (!(Test-Path -LiteralPath (Join-Path $plugin 'QVVR.dll') -PathType Leaf)) { throw 'QVVR.dll is missing; refusing to move an unidentified plugin directory.' }
        if (Get-ChildItem -LiteralPath $plugin -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1) { throw 'Linked content in QVVR directory; refusing to move it.' }
    }
    Write-Host "Game: $root"
    Write-Host 'Only the QVVR plugin will be removed. The game, shared loader and other mods stay untouched.'
    Write-Host $(if ($RemoveConfig) {'QVVR settings will also be backed up and removed.'} else {'QVVR settings will be kept for a future reinstall.'})
    if ($Interactive -and !$WhatIfPreference -and (Read-Host 'Type UNINSTALL to continue') -ne 'UNINSTALL') { Write-Host 'Cancelled.'; return }
    if (!$PSCmdlet.ShouldProcess($root,'Back up and remove the QVVR plugin')) { return }
    Assert-QvvrPcClosed
    $relative='.qvvr-backups/uninstall-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[Guid]::NewGuid().ToString('N')
    $backup=Get-QvvrSafePcPath $root $relative
    New-Item -ItemType Directory -Path $backup | Out-Null
    if ($hasPlugin) {
        $destination=Get-QvvrSafePcPath $root ($relative+'/BepInEx/plugins/QVVR')
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Move-Item -LiteralPath $plugin -Destination $destination
    }
    if ($RemoveConfig -and (Test-Path -LiteralPath $config -PathType Leaf)) {
        $destination=Get-QvvrSafePcPath $root ($relative+'/BepInEx/config/dev.qvvr.prototype.cfg')
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Move-Item -LiteralPath $config -Destination $destination
    }
    Write-Host 'QVVR uninstalled. BepInEx, winhttp.dll and doorstop_config.ini were preserved for other mods.'
    Write-Host "Recoverable backup: $backup"
    Write-Host 'To restore: close QV, then copy the backup contents into this game directory.'
    Write-Host 'You can remove QVVR-specific Steam launch options manually. The game was not launched.'
}

# Dot-sourcing exposes testable functions without changing the machine.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-QvvrPcUninstall -GameDir $GameDir -RemoveConfig:$RemoveConfig -Interactive:$Interactive -WhatIf:$WhatIfPreference }
    catch { Write-Error $_; exit 1 }
}

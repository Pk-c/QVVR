[CmdletBinding()]
param(
    [ValidateSet('PackageOnly', 'CustomTool', 'Ssh', 'Adb')]
    [string]$Mode = 'PackageOnly',
    [string]$ToolPath,
    [string]$ToolArgumentTemplate = 'deploy --app 1494110 --zip "{zip}"',
    [string]$AdbPath = 'adb',
    [string]$AdbSerial,
    [switch]$AdbUsbLegacy,
    [string]$FrameHost = 'frame',
    [string]$FrameUser = 'steamos',
    [string]$RemoteGameDir = '/home/steamos/.local/share/Steam/steamapps/common/QV',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$zip = Join-Path $root 'build\release\QVVR-v0.1.0.zip'
$frameSetup = Join-Path $root 'package-assets\QVVR-Frame-Setup.ps1'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1')
}
if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) {
    throw "Package not found: $zip"
}

if ($Mode -eq 'PackageOnly') {
    Write-Host "Package ready: $zip"
    return
}

if ($Mode -eq 'CustomTool') {
    if (-not $ToolPath -or -not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
        throw 'CustomTool mode requires -ToolPath pointing to the deployment executable.'
    }

    $arguments = $ToolArgumentTemplate.Replace('{zip}', $zip).Replace('{appid}', '1494110')
    Write-Host "Deploying with custom tool: $ToolPath"
    $process = Start-Process -FilePath $ToolPath -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Custom deployment tool failed with exit code $($process.ExitCode)."
    }
    Write-Host 'Custom deployment completed.'
    return
}

if ($RemoteGameDir -notmatch '^/home/steamos/[A-Za-z0-9_./() -]+$') {
    throw "RemoteGameDir must be an explicit path below /home/steamos: $RemoteGameDir"
}

if ($Mode -eq 'Adb') {
    $adb = Get-Command $AdbPath -ErrorAction SilentlyContinue
    if (-not $adb) {
        throw "ADB was not found: $AdbPath. Install Android SDK Platform Tools or pass -AdbPath."
    }

    if ($AdbUsbLegacy) {
        $env:ADB_USB_LEGACY = '1'
        & $adb.Source 'kill-server' | Out-Null
    }

    # Same path as end users: package validation, QV-closed check, recoverable
    # backup, settings preservation and Steam launch options.
    $setupArguments = @{ Action = 'Install'; PackagePath = $zip; AdbPath = $adb.Source; RemoteGameDir = $RemoteGameDir }
    if ($AdbSerial) { $setupArguments.Serial = $AdbSerial }
    & $frameSetup @setupArguments
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw 'Steam Frame installation failed.'
    }
    return
}

$scp = Get-Command scp -ErrorAction SilentlyContinue
$ssh = Get-Command ssh -ErrorAction SilentlyContinue
if (-not $scp -or -not $ssh) {
    throw 'Ssh mode requires the Windows OpenSSH scp and ssh commands.'
}

# The release ZIP holds PC/ + SteamFrame/; upload only the rebuilt game overlay.
function New-FrameOverlayArchive([string]$Release, [string]$Destination) {
    . $frameSetup
    New-QvvrUploadArchive $Release $Destination
}
$overlayZip = Join-Path ([IO.Path]::GetTempPath()) ('qvvr-overlay-' + [Guid]::NewGuid().ToString('N') + '.zip')
New-FrameOverlayArchive $zip $overlayZip

$remoteArchive = '/home/steamos/qvvr-deploy.zip'
$destination = "$FrameUser@$FrameHost"
Write-Host "Uploading the QVVR overlay to $destination..."
& $scp.Source $overlayZip "${destination}:$remoteArchive"
$scpExit = $LASTEXITCODE
Remove-Item -LiteralPath $overlayZip -Force
if ($scpExit -ne 0) {
    throw 'SCP upload failed.'
}

$remoteCommand = "set -eu; test -d '$RemoteGameDir'; if pgrep -f '(^|[[:space:]\\/])QV[.]exe([[:space:]]|$)' >/dev/null; then echo 'QV is running. Close it before deploying; no files were replaced.' >&2; exit 1; fi; if test -f '$RemoteGameDir/BepInEx/config/dev.qvvr.prototype.cfg'; then bsdtar -xf '$remoteArchive' --exclude 'BepInEx/config/dev.qvvr.prototype.cfg' -C '$RemoteGameDir'; else bsdtar -xf '$remoteArchive' -C '$RemoteGameDir'; fi; rm -f '$remoteArchive'"
& $ssh.Source $destination $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw 'Remote extraction failed. The uploaded archive was left in /home/steamos for inspection.'
}

Write-Host "QVVR deployed to ${destination}:$RemoteGameDir"
Write-Host 'Required launch options (set them in Steam, or run SteamFrame option 4 over USB): WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11'

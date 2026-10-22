#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Menu','Install','Uninstall')][string]$Action='Menu',
    [string]$PackagePath,
    [string]$AdbPath,
    [string]$Serial,
    [string]$RemoteGameDir='/home/steamos/.local/share/Steam/steamapps/common/QV',
    [switch]$RemoveConfig
)
$ErrorActionPreference='Stop'

function Get-QvvrInstallFiles {
    foreach ($name in @('0Harmony.dll','0Harmony20.dll','BepInEx.dll','BepInEx.Harmony.dll','BepInEx.Preloader.dll','HarmonyXInterop.dll','Mono.Cecil.dll','Mono.Cecil.Mdb.dll','Mono.Cecil.Pdb.dll','Mono.Cecil.Rocks.dll','MonoMod.RuntimeDetour.dll','MonoMod.Utils.dll')) { "BepInEx/core/$name" }
    'winhttp.dll'; 'doorstop_config.ini'; '.doorstop_version'
    foreach ($name in @('QVVR.dll','QVVR.Native.dll','openvr_api.dll','openxr_loader.dll')) { "BepInEx/plugins/QVVR/$name" }
    foreach ($name in @('BepInEx','UnityDoorstop','HarmonyX','Harmony','BepInEx.Harmony','MonoMod','Mono.Cecil','OpenVR','OpenXR','DirectX-Headers','DirectX-Hash')) { "BepInEx/plugins/QVVR/licenses/$name.txt" }
    'BepInEx/plugins/QVVR/licenses/source/UnityDoorstop-v4.5.0-source.zip'
    'BepInEx/config/dev.qvvr.prototype.cfg'
    'README.txt'; 'RELEASE-NOTES.txt'; 'QVVR-THIRD-PARTY-NOTICES.txt'; 'uninstall.bat'; 'uninstall.ps1'; 'qvvr-launch-options.txt'; 'LICENSE.txt'
    '.qvvr-loader-owner'; 'qvvr-package.json'; 'qvvr-files.sha256'
}

function Test-QvvrInstallArchive([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $allowed=@(Get-QvvrInstallFiles)
    $zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).ProviderPath)
    try {
        $entries=@{}; $hashes=@{}; $total=0L
        foreach ($entry in $zip.Entries) {
            $name=$entry.FullName
            $kind=($entry.ExternalAttributes -shr 16) -band 61440
            if ($kind -notin @(0,32768,16384)) { throw 'Linked/special ZIP entries are not allowed.' }
            if ($name.EndsWith('/')) {
                if ($entry.Length -ne 0 -or !($allowed | Where-Object { $_.StartsWith($name,[StringComparison]::Ordinal) })) { throw 'Unexpected ZIP directory.' }
                continue
            }
            if ($name -cnotin $allowed -or $entries.ContainsKey($name)) { throw "Unsafe, duplicate or unexpected ZIP path: $name" }
            $total+=$entry.Length
            if ($entry.Length -gt 67108864 -or $total -gt 268435456) { throw 'Package exceeds size safety limits.' }
            $entries[$name]=$entry
            $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
            try { $hashes[$name]=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
            finally { $sha.Dispose(); $stream.Dispose() }
        }
        if ($entries.Count -ne $allowed.Count) { throw 'Incomplete QVVR package.' }
        function Read-QvvrZipText([string]$Name) {
            $reader=New-Object IO.StreamReader($entries[$Name].Open())
            try { $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        $listed=@{}
        foreach ($line in (Read-QvvrZipText 'qvvr-files.sha256') -split '\r?\n') {
            if (!$line) { continue }
            if ($line -cnotmatch '^([0-9a-f]{64})  (.+)$') { throw 'Invalid checksum manifest.' }
            $digest=$Matches[1]; $name=$Matches[2]
            if ($name -eq 'qvvr-files.sha256' -or $listed.ContainsKey($name) -or !$hashes.ContainsKey($name) -or $digest -cne $hashes[$name]) { throw 'Package file checksum failed.' }
            $listed[$name]=$true
        }
        if ($listed.Count -ne $entries.Count-1) { throw 'Incomplete checksum manifest.' }
        $metadata=Read-QvvrZipText 'qvvr-package.json' | ConvertFrom-Json
        if ($metadata.name -ne 'QVVR' -or $metadata.steamAppId -ne 1494110 -or $metadata.architecture -ne 'win-x64' -or $metadata.version -notmatch '^\d+\.\d+\.\d+$') { throw 'This is not a supported QVVR package.' }
        if ((Read-QvvrZipText '.qvvr-loader-owner').Trim() -ne "QVVR $($metadata.version) installed BepInEx 5.4.23.5") { throw 'Invalid QVVR ownership marker.' }
        if (Test-Path -LiteralPath "$Path.sha256" -PathType Leaf) {
            $expected=(Get-Content -LiteralPath "$Path.sha256" -Raw).Trim()
            $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($Path)
            if ($expected -cne $actual) { throw 'ZIP checksum sidecar mismatch.' }
        }
        Write-Host "Verified QVVR $($metadata.version): $($entries.Count) files and SHA-256 manifest (not a publisher signature)."
    } finally { $zip.Dispose() }
}

function Find-QvvrAdb([string]$Requested) {
    if ($Requested) { $command=Get-Command $Requested -ErrorAction Stop; return $command.Source }
    $candidates=@((Join-Path $PSScriptRoot 'platform-tools/adb.exe'),(Join-Path $PSScriptRoot 'adb.exe'),(Join-Path $PSScriptRoot '../.deps/android-platform-tools/platform-tools/adb.exe'),(Join-Path $PSScriptRoot '../../.deps/android-platform-tools/platform-tools/adb.exe'))
    if ($env:ANDROID_SDK_ROOT) { $candidates+=Join-Path $env:ANDROID_SDK_ROOT 'platform-tools/adb.exe' }
    if ($env:ANDROID_HOME) { $candidates+=Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe' }
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).ProviderPath } }
    $command=Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw 'ADB not found. Extract official Android SDK Platform Tools beside this script (platform-tools/adb.exe), or supply -AdbPath.'
}

function Invoke-QvvrAdb([string[]]$Arguments) {
    $output=@(& $script:qvvrAdb @script:qvvrTarget @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "ADB failed ($LASTEXITCODE). Check USB authorization and the device connection." }
    return $output
}

function Get-QvvrFrameHelper {
    # Uploaded into a private, unique /tmp directory. Package paths were already
    # allowlisted and hashed on the PC; extraction occurs here, never over QV.
    return @'
#!/bin/sh
set -eu
action=$1
game=$2
session=$3
remove_config=$4
fail() { echo "$*" >&2; exit 1; }
case "$game" in /home/steamos/*|/run/media/*) ;; *) fail 'Unsupported game location.';; esac
game=$(realpath -e "$game")
case "$game" in /home/steamos/*|/run/media/*) ;; *) fail 'Resolved game directory is outside supported Steam storage.';; esac
test -f "$game/QV.exe" && test -d "$game/QV_Data" || fail 'QV.exe / QV_Data missing. Check RemoteGameDir.'
test -d "$session" && test ! -L "$session" || fail 'Invalid temporary session.'
command -v pgrep >/dev/null || fail 'pgrep is required to verify QV is closed.'
closed() {
    if pgrep -f '(^|[[:space:]\\/])QV[.]exe([[:space:]]|$)' >/dev/null; then fail 'QV is running. Close it yourself and retry; no process was terminated.'
    else status=$?; test "$status" = 1 || fail 'Could not verify QV process state; nothing will be replaced.'; fi
}
safe() {
    rel=$1
    case "$rel" in ''|/*|*\\*|../*|*/../*|*/..|..|./*|*/./*) fail 'Unsafe relative file path.';; esac
    current=$game
    rest=$rel
    while :; do
        component=${rest%%/*}
        current=$current/$component
        test ! -L "$current" || fail 'Linked game content detected; refusing to modify it.'
        case "$rest" in */*) rest=${rest#*/};; *) break;; esac
    done
}
closed
if test "$action" = Check; then echo "QV is closed. Game verified: $game"; exit 0; fi
safe '.qvvr-backups'
backup=$game/.qvvr-backups/$action-${session##*/}
test ! -e "$backup" || fail 'Backup destination already exists.'
if test "$action" = Uninstall; then
    safe 'BepInEx/plugins/QVVR'
    safe 'BepInEx/config/dev.qvvr.prototype.cfg'
    plugin=$game/BepInEx/plugins/QVVR
    config=$game/BepInEx/config/dev.qvvr.prototype.cfg
    if test ! -d "$plugin" && { test "$remove_config" != 1 || test ! -f "$config"; }; then echo 'QVVR is already uninstalled. Nothing changed.'; exit 0; fi
    if test -d "$plugin"; then
        test -f "$plugin/QVVR.dll" || fail 'Unidentified plugin directory; QVVR.dll missing.'
        test -z "$(find "$plugin" -type l -print -quit)" || fail 'Linked plugin content; refusing to move it.'
    fi
    closed
    mkdir -p "$backup/BepInEx/plugins"
    if test -d "$plugin"; then mv "$plugin" "$backup/BepInEx/plugins/QVVR"; fi
    if test "$remove_config" = 1 && test -f "$config"; then mkdir -p "$backup/BepInEx/config"; mv "$config" "$backup/BepInEx/config/dev.qvvr.prototype.cfg"; fi
    echo "QVVR uninstalled. Recoverable backup: $backup"
    echo 'Shared BepInEx/loader, other mods and game files were preserved. Settings kept unless RemoveConfig was requested.'
    exit 0
fi
test "$action" = Install || fail 'Unknown action.'
command -v bsdtar >/dev/null || fail 'bsdtar is required on Frame.'
mkdir "$session/stage"
bsdtar -xf "$session/package.zip" -C "$session/stage"
stage=$session/stage
sed 's/\r$//' "$stage/qvvr-files.sha256" >"$session/checksums"
(cd "$stage" && sha256sum -c "$session/checksums") >"$session/verify.log" || fail 'On-device package checksum failed.'
sed 's/^[0-9a-f]*  //' "$session/checksums" >"$session/files"
printf '%s\n' qvvr-files.sha256 >>"$session/files"
# Validate ALL destinations/conflicts before replacing the first file. Shared
# loader differences are never overwritten, even if another mod installed them.
while IFS= read -r file; do
    safe "$file"
    target=$game/$file
    if test -e "$target" && test ! -f "$target"; then fail "Non-file installation conflict: $file"; fi
    if test "$file" = BepInEx/config/dev.qvvr.prototype.cfg && test -f "$target"; then continue; fi
    if test -f "$target" && ! cmp -s "$stage/$file" "$target"; then
        case "$file" in
          BepInEx/core/*|winhttp.dll|doorstop_config.ini|.doorstop_version) fail "Different shared loader file: $file. Review the existing BepInEx installation manually.";;
          README.txt|LICENSE.txt|uninstall.bat|uninstall.ps1)
            safe 'qvvr-files.sha256'
            test -f "$game/qvvr-files.sha256" || fail "Unowned existing file: $file"
            expected=$(awk -v want="$file" '{sub(/\r$/,"")} substr($0,67)==want {print substr($0,1,64)}' "$game/qvvr-files.sha256")
            actual=$(sha256sum "$target"); actual=${actual%% *}
            test "$expected" = "$actual" || fail "Existing documentation was changed or is not owned by QVVR: $file";;
        esac
    fi
done <"$session/files"
closed
mkdir -p "$backup"
: >"$backup/installed-files.txt"
: >"$backup/new-files.txt"
while IFS= read -r file; do
    target=$game/$file
    if test "$file" = BepInEx/config/dev.qvvr.prototype.cfg && test -f "$target"; then continue; fi
    printf '%s\n' "$file" >>"$backup/installed-files.txt"
    if test -f "$target"; then mkdir -p "$backup/$(dirname "$file")"; cp -p "$target" "$backup/$file"
    else printf '%s\n' "$file" >>"$backup/new-files.txt"; fi
done <"$session/files"
# Existing config is excluded and never replaced. A USB disconnect cannot erase
# the on-device backup; installed-files.txt also lists newly added overlay files.
while IFS= read -r file; do
    target=$game/$file
    if test "$file" = BepInEx/config/dev.qvvr.prototype.cfg && test -f "$target"; then continue; fi
    mkdir -p "$(dirname "$target")"
    cp -p "$stage/$file" "$target"
done <"$session/files"
while IFS= read -r file; do
    if test "$file" = BepInEx/config/dev.qvvr.prototype.cfg; then continue; fi
    cmp -s "$stage/$file" "$game/$file" || fail "Installed file verification failed: $file. Backup is in $backup"
done <"$session/files"
echo "QVVR installed and verified. Recoverable overlay backup: $backup"
echo 'Existing QVVR settings and other mods were preserved. QV was not launched.'
'@
}

function Invoke-QvvrFrameSetup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Action,[string]$PackagePath,[string]$AdbPath,[string]$Serial,[string]$RemoteGameDir,[switch]$RemoveConfig)
    if ($Action -eq 'Menu') {
        Write-Host 'QVVR Steam Frame USB setup - close QV first'
        Write-Host '1: Install / update   2: Uninstall (keep settings)   3: Uninstall + remove settings   Enter: cancel'
        switch (Read-Host 'Choose') { '1' {$Action='Install'} '2' {$Action='Uninstall'} '3' {$Action='Uninstall';$RemoveConfig=$true} default {return} }
    }
    if ($RemoteGameDir -notmatch '^/(home/steamos|run/media)/[A-Za-z0-9_./() -]+$' -or $RemoteGameDir -match '(^|/)\.\.?(/|$)') { throw 'Use an explicit game path under /home/steamos or /run/media; path traversal and shell characters are not allowed.' }
    if ($Action -eq 'Install') {
        if (!$PackagePath) {
            $packages=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'QVVR-v*.zip' -File)
            if ($packages.Count -eq 1) { $PackagePath=$packages[0].FullName }
            else { $PackagePath=Read-Host 'Full path to the QVVR release ZIP (without surrounding quotes)' }
        }
        $PackagePath=(Resolve-Path -LiteralPath $PackagePath).ProviderPath
        Test-QvvrInstallArchive $PackagePath
    }
    $script:qvvrAdb=Find-QvvrAdb $AdbPath
    $script:qvvrTarget=@()
    # Steam Frame's USB bridge is more reliable with the legacy ADB transport.
    $previousLegacy=$env:ADB_USB_LEGACY
    $env:ADB_USB_LEGACY='1'
    $local=$null; $remote=$null
    try {
        if (!$Serial) {
            $devices=@(Invoke-QvvrAdb @('devices') | Where-Object { $_ -match '^\S+\s+device\s*$' } | ForEach-Object { ($_ -split '\s+')[0] })
            if ($devices.Count -eq 0) { throw 'No authorized device. Enable Frame Developer Mode/USB debugging, connect USB and authorize this PC in the headset.' }
            if ($devices.Count -eq 1) { $Serial=$devices[0] }
            else { throw 'Multiple ADB devices found. Re-run with -Serial for your Frame; no device was modified.' }
        }
        $script:qvvrTarget=@('-s',$Serial)
        $state=Invoke-QvvrAdb @('get-state')
        if (($state -join '').Trim() -ne 'device') { throw 'The selected device is not ready/authorized.' }
        Write-Host "Selected device: $Serial"
        if (!$PSCmdlet.ShouldProcess("Steam Frame: $RemoteGameDir",$Action+' QVVR (with recoverable backup)')) { return }
        $id=[Guid]::NewGuid().ToString('N')
        $local=Join-Path ([IO.Path]::GetTempPath()) ('qvvr-manager-'+$id)
        New-Item -ItemType Directory -Path $local | Out-Null
        $helper=Join-Path $local 'manage.sh'
        [IO.File]::WriteAllText($helper,((Get-QvvrFrameHelper) -replace "`r`n","`n"),(New-Object Text.UTF8Encoding($false)))
        $remote='/tmp/qvvr-manager-'+$id
        Invoke-QvvrAdb @('shell',"umask 077; mkdir '$remote'") | Out-Host
        Invoke-QvvrAdb @('push',$helper,"$remote/manage.sh") | Out-Host
        $remove=if ($RemoveConfig) {'1'} else {'0'}
        Invoke-QvvrAdb @('shell',"sh '$remote/manage.sh' Check '$RemoteGameDir' '$remote' '$remove'") | Out-Host
        if ($Action -eq 'Install') { Invoke-QvvrAdb @('push',$PackagePath,"$remote/package.zip") | Out-Host }
        Invoke-QvvrAdb @('shell',"sh '$remote/manage.sh' '$Action' '$RemoteGameDir' '$remote' '$remove'") | Out-Host
        if ($Action -eq 'Install') { Write-Host 'Set these Steam launch options manually: WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11' }
        else { Write-Host 'QVVR is removed; shared loader remains. QVVR-specific Steam launch options can be removed manually.' }
        Write-Host 'Done. Start QV yourself when ready.'
    } finally {
        # Only this session's exact /tmp file, never recursive remote deletion.
        if ($remote) {
            try { Invoke-QvvrAdb @('shell',"rm -f '$remote/package.zip'; echo 'Temporary session retained for diagnostics: $remote'") | Out-Host } catch { Write-Warning 'USB disconnected; temporary files may remain on Frame. The overlay backup is still in the game directory.' }
        }
        if ($local) { Write-Host "Local helper retained for diagnostics: $local" }
        $env:ADB_USB_LEGACY=$previousLegacy
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-QvvrFrameSetup -Action $Action -PackagePath $PackagePath -AdbPath $AdbPath -Serial $Serial -RemoteGameDir $RemoteGameDir -RemoveConfig:$RemoveConfig -WhatIf:$WhatIfPreference }
    catch { Write-Error $_; exit 1 }
}

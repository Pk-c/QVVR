#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Menu','Install','Uninstall','LaunchOptions')][string]$Action='Menu',
    [string]$PackagePath,
    [string]$AdbPath,
    [string]$Serial,
    [string]$RemoteGameDir='/home/steamos/.local/share/Steam/steamapps/common/QV',
    [switch]$RemoveConfig,
    [switch]$SkipLaunchOptions
)
$ErrorActionPreference='Stop'
$script:QvvrSteamAppId=1494110
$script:QvvrRequiredLaunchOptions='WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11'

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

# Release ZIP = PC/<overlay> + these files. Only PC/ content is ever uploaded.
function Get-QvvrReleaseExtraNames {
    'README.txt'
    foreach ($name in @('QVVR-Frame-Setup.bat','QVVR-Frame-Setup.ps1','QVVR-Frame-Setup.txt','QVVR-Frame-Defaults.cfg')) { "SteamFrame/$name" }
}

# Steam Frame reference settings, shipped beside this script. Uploaded with an
# install and used ONLY when the headset has no QVVR config yet.
function Get-QvvrFrameDefaults {
    $path=Join-Path $PSScriptRoot 'QVVR-Frame-Defaults.cfg'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $item=Get-Item -LiteralPath $path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked Frame defaults file is not allowed.' }
    if ($item.Length -gt 262144) { throw 'Frame defaults file is too large.' }
    $text=[IO.File]::ReadAllText($path)
    if ($text -notmatch '(?m)^\[VR\]\r?$' -or $text -match '[\x00]') { throw 'Frame defaults file is not a QVVR config.' }
    return $item.FullName
}

function Find-QvvrPackageSource {
    $release=Split-Path -Parent $PSScriptRoot
    $pc=Join-Path $release 'PC'
    if (Test-Path -LiteralPath (Join-Path $pc 'qvvr-package.json') -PathType Leaf) { return $pc }
    $packages=@(Get-ChildItem -LiteralPath $PSScriptRoot,$release -Filter 'QVVR-v*.zip' -File -ErrorAction SilentlyContinue)
    if ($packages.Count -eq 1) { return $packages[0].FullName }
    Write-Host 'The PC folder of the release was not found beside SteamFrame. Extract the WHOLE release ZIP first.'
    return Read-Host 'Full path to the release PC folder or release ZIP (without surrounding quotes)'
}

# Rebuilds the exact overlay ZIP that is uploaded from the extracted PC folder or
# the release ZIP, then validates it with Test-QvvrInstallArchive.
function New-QvvrUploadArchive([string]$Source,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $allowed=@(Get-QvvrInstallFiles)
    $extras=@(Get-QvvrReleaseExtraNames)
    $Source=(Resolve-Path -LiteralPath $Source).ProviderPath
    if (Test-Path -LiteralPath $Destination) { throw "Upload archive already exists: $Destination" }
    $output=[IO.Compression.ZipFile]::Open($Destination,[IO.Compression.ZipArchiveMode]::Create)
    try {
        if (Test-Path -LiteralPath $Source -PathType Container) {
            $root=$Source.TrimEnd('\','/')
            foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -Force) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked content is not allowed in the PC folder: $($item.FullName)" }
                if ($item.PSIsContainer) { continue }
                $name=$item.FullName.Substring($root.Length+1).Replace('\','/')
                if ($name -cnotin $allowed) { throw "Unexpected file in the PC folder: $name. Use a freshly extracted release." }
            }
            foreach ($name in $allowed) {
                $path=Join-Path $root $name
                if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Incomplete PC folder; missing: $name" }
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($output,$path,$name,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } else {
            if (Test-Path -LiteralPath "$Source.sha256" -PathType Leaf) {
                $expected=(Get-Content -LiteralPath "$Source.sha256" -Raw).Trim()
                $actual=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($Source)
                if ($expected -cne $actual) { throw 'Release ZIP checksum sidecar mismatch.' }
            }
            $release=[IO.Compression.ZipFile]::OpenRead($Source)
            try {
                $seen=@{}; $total=0L
                foreach ($entry in $release.Entries) {
                    $name=$entry.FullName
                    $kind=($entry.ExternalAttributes -shr 16) -band 61440
                    if ($kind -notin @(0,32768,16384)) { throw 'Linked/special ZIP entries are not allowed.' }
                    if ($name.EndsWith('/')) { continue }
                    if ($seen.ContainsKey($name)) { throw "Duplicate release ZIP path: $name" }
                    $seen[$name]=$true
                    if ($name -cin $extras) { continue }
                    if (!$name.StartsWith('PC/',[StringComparison]::Ordinal) -or $name.Substring(3) -cnotin $allowed) { throw "Unexpected release ZIP path: $name" }
                    $total+=$entry.Length
                    if ($entry.Length -gt 67108864 -or $total -gt 268435456) { throw 'Package exceeds size safety limits.' }
                    $target=$output.CreateEntry($name.Substring(3),[IO.Compression.CompressionLevel]::Optimal)
                    $in=$entry.Open(); $out=$target.Open()
                    try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
                }
            } finally { $release.Dispose() }
        }
    } finally { $output.Dispose() }
    Test-QvvrInstallArchive $Destination
}

function Test-QvvrInstallArchive([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
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

# Adds the required loader override/graphics API to existing options instead of
# replacing them. Ambiguous combinations are reported, never rewritten.
function Get-QvvrLaunchOptionsPlan([string]$Current) {
    $current=if ($null -eq $Current) { '' } else { $Current.Trim() }
    if (!$current) { return [pscustomobject]@{ Value=$script:QvvrRequiredLaunchOptions; Changed=$true; Conflict=$null } }
    $index=$current.IndexOf('%command%',[StringComparison]::Ordinal)
    if ($index -ge 0) { $pre=$current.Substring(0,$index).Trim(); $post=$current.Substring($index+9).Trim() }
    elseif ($current -match '^[A-Za-z_][A-Za-z0-9_]*=') { return [pscustomobject]@{ Value=$current; Changed=$false; Conflict='Environment variables are set without %command%.' } }
    else { $pre=''; $post=$current }
    if ($post -match '(^|\s)-force-(d3d12|vulkan|glcore|metal)\b') { return [pscustomobject]@{ Value=$current; Changed=$false; Conflict='Another graphics API is forced; QVVR requires -force-d3d11.' } }
    if ($pre -match 'WINEDLLOVERRIDES=') {
        if ($pre -notmatch 'winhttp=n,b') { return [pscustomobject]@{ Value=$current; Changed=$false; Conflict='WINEDLLOVERRIDES is already set without winhttp=n,b.' } }
    } else { $pre=('WINEDLLOVERRIDES="winhttp=n,b" '+$pre).Trim() }
    if ($post -notmatch '(^|\s)-force-d3d11(\s|$)') { $post=($post+' -force-d3d11').Trim() }
    $value=(@($pre,'%command%',$post) | Where-Object { $_ }) -join ' '
    return [pscustomobject]@{ Value=$value; Changed=($value -cne $current); Conflict=$null }
}

# Read-only fallback: Steam rewrites localconfig.vdf while running, so it is
# never edited; it only tells whether the options are already present.
function Get-QvvrVdfLaunchOptions([string]$Text,[string]$AppId) {
    $target=@('userlocalconfigstore','software','valve','steam','apps',$AppId)
    $path=New-Object 'Collections.Generic.List[string]'
    $pending=$null
    foreach ($match in [regex]::Matches($Text,'//[^\n]*|"((?:[^"\\]|\\.)*)"|\{|\}|[^\s{}"]+')) {
        $token=$match.Value
        if ($token.StartsWith('//')) { continue }
        if ($token -eq '{') { if ($null -eq $pending) { throw 'Malformed Steam configuration.' }; $path.Add($pending.ToLowerInvariant()); $pending=$null; continue }
        if ($token -eq '}') { if ($path.Count -eq 0) { throw 'Malformed Steam configuration.' }; $path.RemoveAt($path.Count-1); $pending=$null; continue }
        $value=if ($match.Groups[1].Success) { [regex]::Replace($match.Groups[1].Value,'\\(.)',{ param($m) switch -CaseSensitive ($m.Groups[1].Value) { 'n' {"`n"} 't' {"`t"} 'r' {"`r"} default {$m.Groups[1].Value} } }) } else { $token }
        if ($null -eq $pending) { $pending=$value; continue }
        if ($pending -eq 'LaunchOptions' -and $path.Count -eq $target.Count -and (($path -join '/') -eq ($target -join '/'))) { return $value }
        $pending=$null
    }
    return $null
}

function Get-QvvrConfigLaunchOptions {
    $config=((Invoke-QvvrAdb @('shell',"find /home/steamos/.local/share/Steam/userdata -type f -path '*/config/localconfig.vdf' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -n 1 | cut -f2-")) -join '').Trim()
    if ($config -notmatch '^/home/steamos/\.local/share/Steam/userdata/[0-9]+/config/localconfig\.vdf$') { throw 'No Steam user configuration was found on the Frame.' }
    $file=Join-Path ([IO.Path]::GetTempPath()) ('qvvr-localconfig-'+[Guid]::NewGuid().ToString('N')+'.vdf')
    try {
        Invoke-QvvrAdb @('pull',$config,$file) | Out-Null
        return Get-QvvrVdfLaunchOptions ([IO.File]::ReadAllText($file)) "$script:QvvrSteamAppId"
    } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue -WhatIf:$false }
}

function Invoke-QvvrDevToolsEvaluate([Uri]$Uri,[string]$Expression) {
    $socket=New-Object Net.WebSockets.ClientWebSocket
    $timeout=New-Object Threading.CancellationTokenSource 15000
    try {
        [void]$socket.ConnectAsync($Uri,$timeout.Token).GetAwaiter().GetResult()
        $request=@{ id=1; method='Runtime.evaluate'; params=@{ expression=$Expression; awaitPromise=$true; returnByValue=$true } } | ConvertTo-Json -Compress -Depth 4
        $bytes=[Text.Encoding]::UTF8.GetBytes($request)
        [void]$socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$timeout.Token).GetAwaiter().GetResult()
        $buffer=New-Object byte[] 65536
        while ($true) {
            $stream=New-Object IO.MemoryStream
            do {
                $result=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$timeout.Token).GetAwaiter().GetResult()
                if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'Steam closed the DevTools connection.' }
                $stream.Write($buffer,0,$result.Count)
            } while (!$result.EndOfMessage)
            $message=[Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
            if ($message.id -ne 1) { continue }
            if ($message.error) { throw "Steam rejected the DevTools request: $($message.error.message)" }
            $details=$message.result.exceptionDetails
            if ($details) { $text=if ($details.exception.description) { $details.exception.description } else { $details.text }; throw "Steam script failed: $text" }
            return $message.result.result.value
        }
    } finally { $timeout.Dispose(); $socket.Dispose() }
}

# Steam client's own API through its CEF DevTools port, forwarded over USB.
# Requires Steam running and CEF Remote Debugging enabled in Frame developer settings.
function Invoke-QvvrSteamScript([string]$Expression) {
    $errors=@()
    foreach ($remotePort in @(8080,8081)) {
        $localPort=$null
        try {
            $forward=((Invoke-QvvrAdb @('forward','tcp:0',"tcp:$remotePort")) -join '').Trim()
            if ($forward -notmatch '^\d+$') { throw 'ADB did not return a forwarded port.' }
            $localPort=[int]$forward
            $request=[Net.HttpWebRequest]::Create("http://127.0.0.1:$localPort/json/list")
            $request.Timeout=5000; $request.ReadWriteTimeout=5000; $request.Proxy=$null
            $response=$request.GetResponse()
            try { $reader=New-Object IO.StreamReader($response.GetResponseStream()); $list=$reader.ReadToEnd(); $reader.Dispose() } finally { $response.Dispose() }
            $target=$null
            foreach ($entry in ($list | ConvertFrom-Json)) { if ("$($entry.title)" -like '*SharedJSContext*' -and $entry.webSocketDebuggerUrl) { $target=$entry; break } }
            if (!$target) { $errors+="Port $remotePort has no SharedJSContext."; continue }
            $builder=New-Object UriBuilder ([Uri]$target.webSocketDebuggerUrl)
            $builder.Host='127.0.0.1'; $builder.Port=$localPort
            return Invoke-QvvrDevToolsEvaluate $builder.Uri $Expression
        } catch { $errors+=$_.Exception.Message }
        finally { if ($localPort) { try { Invoke-QvvrAdb @('forward','--remove',"tcp:$localPort") | Out-Null } catch { } } }
    }
    throw ('Steam DevTools are not reachable over USB. '+(($errors | Select-Object -Unique) -join ' '))
}

function Get-QvvrSteamLaunchOptions {
    $js=@'
(async () => {
  const api = window.SteamClient && window.SteamClient.Apps;
  if (!api || typeof api.RegisterForAppDetails !== "function") throw new Error("SteamClient.Apps.RegisterForAppDetails is unavailable.");
  return await new Promise((resolve, reject) => {
    let registration = null, done = false;
    const release = () => setTimeout(() => registration && registration.unregister && registration.unregister(), 0);
    const timer = setTimeout(() => { if (!done) { done = true; release(); reject(new Error("Steam did not report QV details.")); } }, 6000);
    registration = api.RegisterForAppDetails(__APPID__, (details) => {
      if (done) return;
      done = true; clearTimeout(timer); release();
      resolve((details && details.strLaunchOptions) || "");
    });
  });
})()
'@
    $value=Invoke-QvvrSteamScript ($js.Replace('__APPID__',"$script:QvvrSteamAppId"))
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Set-QvvrSteamLaunchOptions([string]$Value) {
    $js=@'
(async () => {
  const api = window.SteamClient && window.SteamClient.Apps;
  if (!api || typeof api.SetAppLaunchOptions !== "function" || typeof api.RegisterForAppDetails !== "function") throw new Error("SteamClient.Apps launch-option API is unavailable.");
  const expected = __EXPECTED__;
  return await new Promise((resolve) => {
    let registration = null, armed = false, settled = false, actual = "";
    const finish = (ok) => { if (settled) return; settled = true; clearTimeout(timer); setTimeout(() => registration && registration.unregister && registration.unregister(), 0); resolve({ ok: ok, actual: actual }); };
    const timer = setTimeout(() => finish(false), 6000);
    registration = api.RegisterForAppDetails(__APPID__, (details) => {
      actual = (details && details.strLaunchOptions) || "";
      if (armed && actual === expected) finish(true);
    });
    armed = true;
    api.SetAppLaunchOptions(__APPID__, expected);
  });
})()
'@
    $expected=ConvertTo-Json -InputObject $Value -Compress
    $result=Invoke-QvvrSteamScript ($js.Replace('__APPID__',"$script:QvvrSteamAppId").Replace('__EXPECTED__',$expected))
    if (!$result -or !$result.ok) { throw "Steam did not confirm the launch-option change. Current value: $(if ($result) { $result.actual } else { 'unknown' })" }
}

# Never fails an installation: files are already verified at this point.
function Update-QvvrFrameLaunchOptions {
    $manual="Set them manually in Steam > QV > Properties > Launch options: $script:QvvrRequiredLaunchOptions"
    try { $current=Get-QvvrSteamLaunchOptions }
    catch {
        $reason=$_.Exception.Message
        $saved=$null
        try { $saved=Get-QvvrConfigLaunchOptions } catch { }
        if ($null -ne $saved) {
            $plan=Get-QvvrLaunchOptionsPlan $saved
            if (!$plan.Changed -and !$plan.Conflict) { Write-Host "Steam launch options already set (saved Steam config): $saved"; return $true }
        }
        Write-Warning "Steam launch options were not changed: $reason"
        Write-Warning 'Keep Steam open, enable CEF Remote Debugging in the Frame developer settings, then run menu option 4 (or -Action LaunchOptions).'
        Write-Warning $manual
        return $false
    }
    $plan=Get-QvvrLaunchOptionsPlan $current
    if ($plan.Conflict) {
        Write-Warning "Steam launch options were not changed: $($plan.Conflict) Current value: $current"
        Write-Warning $manual
        return $false
    }
    if (!$plan.Changed) { Write-Host "Steam launch options already set: $current"; return $true }
    try { Set-QvvrSteamLaunchOptions $plan.Value }
    catch { Write-Warning "Steam launch options were not changed: $($_.Exception.Message)"; Write-Warning $manual; return $false }
    $previous=if ($current) { $current } else { '(empty)' }
    Write-Host "Steam launch options set: $($plan.Value)  (previous: $previous). Steam stayed open."
    return $true
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
# A first Frame install starts from the Steam Frame reference profile shipped
# beside the installer. An existing config is never replaced (skipped below).
if test -f "$session/frame-defaults.cfg" && test ! -L "$session/frame-defaults.cfg"; then
    cp "$session/frame-defaults.cfg" "$stage/BepInEx/config/dev.qvvr.prototype.cfg"
fi
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
    param([string]$Action,[string]$PackagePath,[string]$AdbPath,[string]$Serial,[string]$RemoteGameDir,[switch]$RemoveConfig,[switch]$SkipLaunchOptions)
    if ($Action -eq 'Menu') {
        Write-Host 'QVVR Steam Frame USB setup - close QV first'
        Write-Host '1: Install / update (+ Steam launch options)   2: Uninstall (keep settings)'
        Write-Host '3: Uninstall + remove settings   4: Steam launch options only   Enter: cancel'
        switch (Read-Host 'Choose') { '1' {$Action='Install'} '2' {$Action='Uninstall'} '3' {$Action='Uninstall';$RemoveConfig=$true} '4' {$Action='LaunchOptions'} default {return} }
    }
    if ($RemoteGameDir -notmatch '^/(home/steamos|run/media)/[A-Za-z0-9_./() -]+$' -or $RemoteGameDir -match '(^|/)\.\.?(/|$)') { throw 'Use an explicit game path under /home/steamos or /run/media; path traversal and shell characters are not allowed.' }
    $upload=$null
    $local=$null; $remote=$null
    $previousLegacy=$env:ADB_USB_LEGACY
    try {
        if ($Action -eq 'Install') {
            if (!$PackagePath) { $PackagePath=Find-QvvrPackageSource }
            $local=Join-Path ([IO.Path]::GetTempPath()) ('qvvr-manager-'+[Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $local -WhatIf:$false | Out-Null
            $upload=Join-Path $local 'package.zip'
            New-QvvrUploadArchive $PackagePath $upload
        }
        $script:qvvrAdb=Find-QvvrAdb $AdbPath
        $script:qvvrTarget=@()
        # Steam Frame's USB bridge is more reliable with the legacy ADB transport.
        $env:ADB_USB_LEGACY='1'
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
        if ($Action -eq 'LaunchOptions') {
            if (!$PSCmdlet.ShouldProcess('Steam on Frame: QV (app 1494110)','Set QVVR launch options')) { return }
            if (!(Update-QvvrFrameLaunchOptions)) { throw 'Steam launch options were not applied.' }
            Write-Host 'Done. Start QV yourself when ready.'
            return
        }
        if (!$PSCmdlet.ShouldProcess("Steam Frame: $RemoteGameDir",$Action+' QVVR (with recoverable backup)')) { return }
        if (!$local) {
            $local=Join-Path ([IO.Path]::GetTempPath()) ('qvvr-manager-'+[Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $local -WhatIf:$false | Out-Null
        }
        $id=Split-Path -Leaf $local
        $helper=Join-Path $local 'manage.sh'
        [IO.File]::WriteAllText($helper,((Get-QvvrFrameHelper) -replace "`r`n","`n"),(New-Object Text.UTF8Encoding($false)))
        $remote='/tmp/'+$id
        Invoke-QvvrAdb @('shell',"umask 077; mkdir '$remote'") | Out-Host
        Invoke-QvvrAdb @('push',$helper,"$remote/manage.sh") | Out-Host
        $remove=if ($RemoveConfig) {'1'} else {'0'}
        Invoke-QvvrAdb @('shell',"sh '$remote/manage.sh' Check '$RemoteGameDir' '$remote' '$remove'") | Out-Host
        if ($Action -eq 'Install') {
            Invoke-QvvrAdb @('push',$upload,"$remote/package.zip") | Out-Host
            $defaults=Get-QvvrFrameDefaults
            if ($defaults) { Invoke-QvvrAdb @('push',$defaults,"$remote/frame-defaults.cfg") | Out-Host }
        }
        Invoke-QvvrAdb @('shell',"sh '$remote/manage.sh' '$Action' '$RemoteGameDir' '$remote' '$remove'") | Out-Host
        if ($Action -eq 'Install') {
            if ($SkipLaunchOptions) { Write-Host "Steam launch options skipped. Required: $script:QvvrRequiredLaunchOptions" }
            else { Update-QvvrFrameLaunchOptions | Out-Null }
        }
        else { Write-Host 'QVVR is removed; shared loader remains. QVVR-specific Steam launch options can be removed manually.' }
        Write-Host 'Done. Start QV yourself when ready.'
    } finally {
        # Only this session's exact /tmp file, never recursive remote deletion.
        if ($remote) {
            try { Invoke-QvvrAdb @('shell',"rm -f '$remote/package.zip'; echo 'Temporary session retained for diagnostics: $remote'") | Out-Host } catch { Write-Warning 'USB disconnected; temporary files may remain on Frame. The overlay backup is still in the game directory.' }
        }
        if ($upload) { Remove-Item -LiteralPath $upload -Force -ErrorAction SilentlyContinue -WhatIf:$false }
        if ($local -and (Test-Path -LiteralPath (Join-Path $local 'manage.sh'))) { Write-Host "Local helper retained for diagnostics: $local" }
        $env:ADB_USB_LEGACY=$previousLegacy
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-QvvrFrameSetup -Action $Action -PackagePath $PackagePath -AdbPath $AdbPath -Serial $Serial -RemoteGameDir $RemoteGameDir -RemoveConfig:$RemoveConfig -SkipLaunchOptions:$SkipLaunchOptions -WhatIf:$WhatIfPreference }
    catch { Write-Error $_; exit 1 }
}

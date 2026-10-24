[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'package-assets/uninstall.ps1')
. (Join-Path $root 'package-assets/QVVR-Frame-Setup.ps1')
. (Join-Path $PSScriptRoot 'package-layout.ps1')
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$testRoot=Join-Path $root ('artifacts/installer-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:checks=0
function Assert-Installer([bool]$Condition,[string]$Message){$script:checks++;if(!$Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Operation,[string]$Message){$rejected=$false;try{& $Operation}catch{$rejected=$true};Assert-Installer $rejected $Message}
function Write-Fixture([string]$Game,[string]$File,[string]$Text){
 $path=Join-Path $Game $File
 New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
 [IO.File]::WriteAllText($path,$Text)
}
function New-Game([string]$Name){
 $game=Join-Path $testRoot $Name
 New-Item -ItemType Directory -Path (Join-Path $game 'QV_Data') -Force | Out-Null
 foreach($file in @('QV.exe','BepInEx/plugins/QVVR/QVVR.dll','BepInEx/plugins/QVVR/QVVR.Native.dll','BepInEx/plugins/OtherMod/keep.dll','BepInEx/core/BepInEx.dll','winhttp.dll','doorstop_config.ini','BepInEx/config/dev.qvvr.prototype.cfg')){Write-Fixture $game $file "fixture:$file"}
 return $game
}
# Only fake process state is queried; no game or headset is started/stopped.
$script:fakeRunning=$false
function Get-Process {[CmdletBinding()]param([string]$Name);if($script:fakeRunning){[pscustomobject]@{Name='QV'}}}
$game=New-Game 'PC game [spaces]'
$before=(Get-FileHash -LiteralPath (Join-Path $game 'QV.exe')).Hash
Invoke-QvvrPcUninstall -GameDir $game -WhatIf
Assert-Installer (Test-Path -LiteralPath (Join-Path $game 'BepInEx/plugins/QVVR/QVVR.dll')) 'WhatIf removed the plugin.'
Assert-Installer (!(Test-Path -LiteralPath (Join-Path $game '.qvvr-backups'))) 'WhatIf created a backup.'
$script:fakeRunning=$true
Assert-Rejected {Invoke-QvvrPcUninstall -GameDir $game} 'Running QV must block uninstall.'
$script:fakeRunning=$false
Assert-Rejected {Get-QvvrSafePcPath $game '../escape'} 'Traversal must be rejected.'
Assert-Rejected {Get-QvvrSafePcPath $game 'C:\escape'} 'Absolute paths must be rejected.'
Invoke-QvvrPcUninstall -GameDir $game
Assert-Installer (!(Test-Path -LiteralPath (Join-Path $game 'BepInEx/plugins/QVVR'))) 'Plugin directory not removed.'
Assert-Installer ((Get-FileHash -LiteralPath (Join-Path $game 'QV.exe')).Hash -eq $before) 'Original game changed.'
foreach($file in @('BepInEx/plugins/OtherMod/keep.dll','BepInEx/core/BepInEx.dll','winhttp.dll','doorstop_config.ini','BepInEx/config/dev.qvvr.prototype.cfg')){Assert-Installer ((Get-Content -LiteralPath (Join-Path $game $file) -Raw) -eq "fixture:$file") "Unrelated/settings file changed: $file"}
$backups=@(Get-ChildItem -LiteralPath (Join-Path $game '.qvvr-backups') -Directory -Force)
Assert-Installer ($backups.Count -eq 1) 'Expected exactly one uninstall backup.'
Assert-Installer (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'BepInEx/plugins/QVVR/QVVR.dll')) 'Plugin not recoverable.'
Invoke-QvvrPcUninstall -GameDir $game
Assert-Installer (@(Get-ChildItem -LiteralPath (Join-Path $game '.qvvr-backups') -Directory -Force).Count -eq 1) 'Repeated uninstall must be idempotent.'
Invoke-QvvrPcUninstall -GameDir $game -RemoveConfig
Assert-Installer (!(Test-Path -LiteralPath (Join-Path $game 'BepInEx/config/dev.qvvr.prototype.cfg'))) 'RemoveConfig failed.'
Assert-Installer (@(Get-ChildItem -LiteralPath (Join-Path $game '.qvvr-backups') -File -Recurse -Force | Where-Object Name -eq 'dev.qvvr.prototype.cfg').Count -eq 1) 'Removed settings not backed up.'
$junctionGame=New-Game 'linked-game'
$external=Join-Path $testRoot 'external-safe-fixture'
New-Item -ItemType Directory -Path $external | Out-Null
New-Item -ItemType Junction -Path (Join-Path $junctionGame '.qvvr-backups') -Target $external | Out-Null
Assert-Rejected {Invoke-QvvrPcUninstall -GameDir $junctionGame} 'Linked backup path must be rejected.'
Assert-Installer (Test-Path -LiteralPath (Join-Path $junctionGame 'BepInEx/plugins/QVVR/QVVR.dll')) 'Link rejection must precede plugin movement.'

$zipPath=Join-Path $root 'build/release/QVVR-v0.1.0.zip'
$overlayZip=Join-Path $testRoot 'overlay-from-release.zip'
New-QvvrUploadArchive $zipPath $overlayZip
$expected=@((Get-QvvrPackageFiles $root).Keys)+@('.qvvr-loader-owner','qvvr-package.json','qvvr-files.sha256')
Assert-Installer (@(Compare-Object ($expected | Sort-Object) ((Get-QvvrInstallFiles) | Sort-Object)).Count -eq 0) 'Installer/package allowlists diverged.'
Assert-Installer (@(Compare-Object (@((Get-QvvrReleaseExtraFiles $root).Keys) | Sort-Object) ((Get-QvvrReleaseExtraNames) | Sort-Object)).Count -eq 0) 'Installer/package release extras diverged.'
# Extracted release: the default source is the PC folder beside SteamFrame.
$extracted=Join-Path $testRoot 'extracted release'
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$extracted)
$fromFolder=Join-Path $testRoot 'overlay-from-folder.zip'
New-QvvrUploadArchive (Join-Path $extracted 'PC') $fromFolder
Write-Fixture (Join-Path $extracted 'PC') 'BepInEx/plugins/QVVR/extra.dll' 'unexpected'
Assert-Rejected {New-QvvrUploadArchive (Join-Path $extracted 'PC') (Join-Path $testRoot 'extra.zip')} 'Unexpected PC folder file must be rejected.'
Remove-Item -LiteralPath (Join-Path $extracted 'PC/BepInEx/plugins/QVVR/extra.dll')
$incomplete=Join-Path $testRoot 'incomplete release'
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$incomplete)
Remove-Item -LiteralPath (Join-Path $incomplete 'PC/LICENSE.txt')
Assert-Rejected {New-QvvrUploadArchive (Join-Path $incomplete 'PC') (Join-Path $testRoot 'missing.zip')} 'Incomplete PC folder must be rejected.'
foreach($bad in @('PC/../QV.exe','PC/extra.txt','SteamFrame/adb.exe','QVVR.dll')){
 $badRelease=Join-Path $testRoot ([Guid]::NewGuid().ToString('N')+'.zip')
 Copy-Item -LiteralPath $zipPath -Destination $badRelease
 $archive=[IO.Compression.ZipFile]::Open($badRelease,[IO.Compression.ZipArchiveMode]::Update)
 try{$entry=$archive.CreateEntry($bad);$stream=$entry.Open();$stream.WriteByte(1);$stream.Dispose()}finally{$archive.Dispose()}
 Assert-Rejected {New-QvvrUploadArchive $badRelease (Join-Path $testRoot ([Guid]::NewGuid().ToString('N')+'.zip'))} "Unexpected release entry must be rejected: $bad"
}
foreach($bad in @('../QV.exe','extra.txt','README.TXT')){
 $badZip=Join-Path $testRoot ([Guid]::NewGuid().ToString('N')+'.zip')
 $archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
 try{$entry=$archive.CreateEntry($bad);$stream=$entry.Open();$stream.WriteByte(1);$stream.Dispose()}finally{$archive.Dispose()}
 Assert-Rejected {Test-QvvrInstallArchive $badZip} 'Unsafe ZIP must be rejected.'
}
$badZip=Join-Path $testRoot 'corrupted.zip'
Copy-Item -LiteralPath $overlayZip -Destination $badZip
$archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Update)
try{$archive.GetEntry('BepInEx/plugins/QVVR/QVVR.dll').Delete();$entry=$archive.CreateEntry('BepInEx/plugins/QVVR/QVVR.dll');$stream=$entry.Open();$stream.WriteByte(1);$stream.Dispose()}finally{$archive.Dispose()}
Assert-Rejected {Test-QvvrInstallArchive $badZip} 'Corrupted package must be rejected.'
$badZip=Join-Path $testRoot 'linked.zip'
$archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
try{$entry=$archive.CreateEntry('README.txt');$entry.ExternalAttributes=-1610612736}finally{$archive.Dispose()}
Assert-Rejected {Test-QvvrInstallArchive $badZip} 'Symlink ZIP entries must be rejected.'

# Launch-option merge and read-only Steam config parsing.
$required='WINEDLLOVERRIDES="winhttp=n,b" %command% -force-d3d11'
foreach($case in @(
 @('',$required,$true),
 @($required,$required,$false),
 @('-skipintro','WINEDLLOVERRIDES="winhttp=n,b" %command% -skipintro -force-d3d11',$true),
 @('PROTON_LOG=1 %command% -force-gfx-direct','WINEDLLOVERRIDES="winhttp=n,b" PROTON_LOG=1 %command% -force-gfx-direct -force-d3d11',$true),
 @('WINEDLLOVERRIDES="dinput8=n,b;winhttp=n,b" %command% -force-d3d11','WINEDLLOVERRIDES="dinput8=n,b;winhttp=n,b" %command% -force-d3d11',$false)
)){
 $plan=Get-QvvrLaunchOptionsPlan $case[0]
 Assert-Installer (!$plan.Conflict -and $plan.Value -ceq $case[1] -and $plan.Changed -eq $case[2]) "Launch-option merge failed for '$($case[0])': '$($plan.Value)'"
}
foreach($conflict in @('%command% -force-vulkan','WINEDLLOVERRIDES="dinput8=n,b" %command%','PROTON_LOG=1')){
 $plan=Get-QvvrLaunchOptionsPlan $conflict
 Assert-Installer ($plan.Conflict -and !$plan.Changed -and $plan.Value -ceq $conflict) "Conflicting launch options must be left unchanged: $conflict"
}
$vdf=@'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"1494110"		"00ff"
				"apps"
				{
					"791240"
					{
						"LaunchOptions"		"other"
					}
					"1494110"
					{
						"cloud" { "last_sync_state" "synchronized" }
						"LaunchOptions"		"WINEDLLOVERRIDES=\"winhttp=n,b\" %command% -force-d3d11"
					}
				}
			}
		}
	}
}
'@
Assert-Installer ((Get-QvvrVdfLaunchOptions $vdf '1494110') -ceq $required) 'Steam config launch options were not parsed.'
Assert-Installer ($null -eq (Get-QvvrVdfLaunchOptions $vdf '42')) 'Unknown app must have no launch options.'

# Exercise real PC-side orchestration with an ADB boundary double. Remote shell
# operations themselves are tested separately; nothing touches a physical Frame.
$script:trace=New-Object 'Collections.Generic.List[string]'
$script:devices=@('fake-frame device')
function Find-QvvrAdb([string]$Requested){return 'fake-adb'}
$script:steamOptions='';$script:steamReachable=$true;$script:savedOptions=$null;$script:setOptions=New-Object 'Collections.Generic.List[string]'
function Get-QvvrSteamLaunchOptions{$script:trace.Add('steam-get');if(!$script:steamReachable){throw 'Fixture: Steam unreachable'};return $script:steamOptions}
function Set-QvvrSteamLaunchOptions([string]$Value){$script:trace.Add('steam-set');$script:setOptions.Add($Value);$script:steamOptions=$Value}
function Get-QvvrConfigLaunchOptions{return $script:savedOptions}
function Invoke-QvvrAdb([string[]]$Arguments){
 $script:trace.Add(($Arguments -join '|'))
 if($Arguments[0] -eq 'devices'){return $script:devices}
 if($Arguments[0] -eq 'get-state'){return 'device'}
 if($script:fakeRunning -and $Arguments[0] -eq 'shell' -and $Arguments[1] -match "manage.sh' Check"){throw 'Fixture: QV running'}
}
Invoke-QvvrFrameSetup -Action Install -PackagePath $zipPath -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV' -WhatIf
Assert-Installer (!($script:trace | Where-Object {$_ -match '^(shell|push)\|'})) 'Frame WhatIf uploaded/modified files.'
$script:trace.Clear();$script:fakeRunning=$true
Assert-Rejected {Invoke-QvvrFrameSetup -Action Install -PackagePath $zipPath -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'} 'Running Frame game must refuse.'
Assert-Installer (!($script:trace | Where-Object {$_ -match '^push\|.*\.zip\|'})) 'Archive uploaded before game-closed check.'
$script:fakeRunning=$false;$script:trace.Clear()
Invoke-QvvrFrameSetup -Action Install -PackagePath $zipPath -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'
$recorded=$script:trace.ToArray()
$checkIndex=-1;$pushIndex=-1;$installIndex=-1
for($i=0;$i -lt $recorded.Count;$i++){
 if($recorded[$i] -match "manage.sh' Check"){$checkIndex=$i}
 if($recorded[$i] -match '^push\|.*\.zip\|'){$pushIndex=$i}
 if($recorded[$i] -match "manage.sh' 'Install'"){$installIndex=$i}
}
Assert-Installer ($checkIndex -ge 0 -and $checkIndex -lt $pushIndex -and $pushIndex -lt $installIndex) 'Frame operation order must be check -> upload -> install.'
Assert-Installer (!($recorded | Where-Object {$_ -match 'kill-server|rm -rf|am start|steam://'})) 'Unexpected destructive/server/launch command.'
$setIndex=[Array]::IndexOf($recorded,'steam-set')
Assert-Installer ($setIndex -gt $installIndex) 'Launch options must be applied after the verified installation.'
Assert-Installer ($script:setOptions.Count -eq 1 -and $script:setOptions[0] -ceq $required) 'Empty launch options must be set to the QVVR requirement.'
$script:trace.Clear();$script:setOptions.Clear()
Invoke-QvvrFrameSetup -Action Install -PackagePath (Join-Path $extracted 'PC') -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV' -SkipLaunchOptions
Assert-Rejected {Invoke-QvvrFrameSetup -Action Install -PackagePath (Join-Path $incomplete 'PC') -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'} 'Incomplete PC folder must refuse installation.'
Assert-Installer (!($script:trace | Where-Object {$_ -match '^steam-'})) 'SkipLaunchOptions/refused install must not touch Steam.'
$script:trace.Clear()
Invoke-QvvrFrameSetup -Action LaunchOptions -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'
Assert-Installer ($script:setOptions.Count -eq 0 -and !($script:trace | Where-Object {$_ -match 'manage.sh|^push'})) 'Already-set launch options must not be rewritten or touch game files.'
$script:steamOptions='%command% -force-vulkan'
Assert-Rejected {Invoke-QvvrFrameSetup -Action LaunchOptions -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'} 'Conflicting launch options must be reported.'
Assert-Installer ($script:setOptions.Count -eq 0) 'Conflicting launch options must not be changed.'
$script:steamOptions='';Invoke-QvvrFrameSetup -Action LaunchOptions -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV' -WhatIf
Assert-Installer ($script:setOptions.Count -eq 0) 'WhatIf must not change launch options.'
$script:steamReachable=$false;$script:savedOptions=$required
Assert-Installer (Update-QvvrFrameLaunchOptions) 'Saved Steam config with the options must count as already set.'
$script:savedOptions=''
Assert-Installer (!(Update-QvvrFrameLaunchOptions)) 'Unreachable Steam without saved options must report failure.'
Assert-Installer ($script:setOptions.Count -eq 0) 'Unreachable Steam must not be changed.'
$script:steamReachable=$true
$script:trace.Clear();$script:devices=@('one device','two device')
Assert-Rejected {Invoke-QvvrFrameSetup -Action Uninstall -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'} 'Ambiguous devices must refuse.'
Assert-Installer (!($script:trace | Where-Object {$_ -match '^(shell|push)\|'})) ('Multiple-device rejection must precede remote mutation: '+($script:trace -join ';'))
Assert-Installer ($script:trace.Count -eq 1) 'Ambiguous-device check should only list devices.'
$script:trace.Clear()
Assert-Rejected {Invoke-QvvrFrameSetup -Action Uninstall -RemoteGameDir '/home/steamos/../other'} 'Remote traversal must refuse.'
Assert-Installer ($script:trace.Count -eq 0) 'Unsafe remote path must be rejected before contacting ADB.'
Write-Host "Installer/archive/PC uninstall/ADB orchestration: $script:checks assertions passed. Fixtures retained: $testRoot"
Write-Host 'No real game, Frame deployment or headset acceptance was performed.'

[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'package-assets/uninstall.ps1')
. (Join-Path $root 'package-assets/QVVR-Frame-Setup.ps1')
. (Join-Path $PSScriptRoot 'package-layout.ps1')
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
Test-QvvrInstallArchive $zipPath
$expected=@((Get-QvvrPackageFiles $root).Keys)+@('.qvvr-loader-owner','qvvr-package.json','qvvr-files.sha256')
Assert-Installer (@(Compare-Object ($expected | Sort-Object) ((Get-QvvrInstallFiles) | Sort-Object)).Count -eq 0) 'Installer/package allowlists diverged.'
foreach($bad in @('../QV.exe','extra.txt','README.TXT')){
 $badZip=Join-Path $testRoot ([Guid]::NewGuid().ToString('N')+'.zip')
 $archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
 try{$entry=$archive.CreateEntry($bad);$stream=$entry.Open();$stream.WriteByte(1);$stream.Dispose()}finally{$archive.Dispose()}
 Assert-Rejected {Test-QvvrInstallArchive $badZip} 'Unsafe ZIP must be rejected.'
}
$badZip=Join-Path $testRoot 'corrupted.zip'
Copy-Item -LiteralPath $zipPath -Destination $badZip
$archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Update)
try{$archive.GetEntry('BepInEx/plugins/QVVR/QVVR.dll').Delete();$entry=$archive.CreateEntry('BepInEx/plugins/QVVR/QVVR.dll');$stream=$entry.Open();$stream.WriteByte(1);$stream.Dispose()}finally{$archive.Dispose()}
Assert-Rejected {Test-QvvrInstallArchive $badZip} 'Corrupted package must be rejected.'
$badZip=Join-Path $testRoot 'linked.zip'
$archive=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
try{$entry=$archive.CreateEntry('README.txt');$entry.ExternalAttributes=-1610612736}finally{$archive.Dispose()}
Assert-Rejected {Test-QvvrInstallArchive $badZip} 'Symlink ZIP entries must be rejected.'

$tools=Get-QvvrFrameToolFiles $root
$toolZip=Join-Path $root 'build/release/QVVR-Frame-Setup.zip'
$archive=[IO.Compression.ZipFile]::OpenRead($toolZip)
try{
 Assert-Installer ($archive.Entries.Count -eq $tools.Count) 'Unexpected Frame tools inventory.'
 foreach($file in $tools.GetEnumerator()){
  $reader=New-Object IO.StreamReader($archive.GetEntry($file.Key).Open())
  try{Assert-Installer ($reader.ReadToEnd() -ceq (Get-Content -LiteralPath $file.Value -Raw)) 'Packaged Frame tool differs from source.'}finally{$reader.Dispose()}
 }
}finally{$archive.Dispose()}

# Exercise real PC-side orchestration with an ADB boundary double. Remote shell
# operations themselves are tested separately; nothing touches a physical Frame.
$script:trace=New-Object 'Collections.Generic.List[string]'
$script:devices=@('fake-frame device')
function Find-QvvrAdb([string]$Requested){return 'fake-adb'}
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
$script:trace.Clear();$script:devices=@('one device','two device')
Assert-Rejected {Invoke-QvvrFrameSetup -Action Uninstall -RemoteGameDir '/home/steamos/.local/share/Steam/steamapps/common/QV'} 'Ambiguous devices must refuse.'
Assert-Installer (!($script:trace | Where-Object {$_ -match '^(shell|push)\|'})) ('Multiple-device rejection must precede remote mutation: '+($script:trace -join ';'))
Assert-Installer ($script:trace.Count -eq 1) 'Ambiguous-device check should only list devices.'
$script:trace.Clear()
Assert-Rejected {Invoke-QvvrFrameSetup -Action Uninstall -RemoteGameDir '/home/steamos/../other'} 'Remote traversal must refuse.'
Assert-Installer ($script:trace.Count -eq 0) 'Unsafe remote path must be rejected before contacting ADB.'
Write-Host "Installer/archive/PC uninstall/ADB orchestration: $script:checks assertions passed. Fixtures retained: $testRoot"
Write-Host 'No real game, Frame deployment or headset acceptance was performed.'

[CmdletBinding()]
param([string]$ZipPath,[ValidateSet('Debug','Release')][string]$Configuration='Release')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$ZipPath){$ZipPath=Join-Path $root 'build/release/QVVR-v0.1.0.zip'}
. (Join-Path $PSScriptRoot 'package-layout.ps1')
$inputs=Get-QvvrPackageFiles $root $Configuration
$expected=@($inputs.Keys)+@('.qvvr-loader-owner','qvvr-package.json','qvvr-files.sha256')

function Assert-QvvrEntryNames([string[]]$Names,[string[]]$Allowed){
 $seen=@{}
 foreach($name in $Names){
  if($name.Contains('\') -or $name.StartsWith('/') -or $name.Contains(':') -or $name -match '(^|/)\.\.?(/|$)'){throw 'Unsafe archive path.'}
  if($seen.ContainsKey($name)){throw 'Duplicate/case-colliding archive path.'};$seen[$name]=$true
  if($name -cnotin $Allowed){throw "Unexpected archive file: $name"}
 }
 if($seen.Count -ne $Allowed.Count){throw 'Archive file inventory incomplete.'}
}
# Exercise the fail-closed path gate independently of the current archive.
foreach($bad in @('../QV.exe','/QV.exe','C:/QV.exe','BepInEx\secret.cfg','logs.txt','README.TXT')){
 $rejected=$false;try{Assert-QvvrEntryNames (@($expected)+$bad) $expected}catch{$rejected=$true}
 if(!$rejected){throw 'Archive path rejection self-test failed.'}
}
$rejected=$false;try{Assert-QvvrEntryNames (@($expected)+$expected[0]) $expected}catch{$rejected=$true}
if(!$rejected){throw 'Duplicate archive path self-test failed.'}

$archive=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ZipPath))
try {
 $entries=@{}
 foreach($entry in $archive.Entries){
  if($entry.FullName.EndsWith('/')){
   if($entry.Length -ne 0 -or !($expected | Where-Object {$_.StartsWith($entry.FullName,[StringComparison]::Ordinal)})){throw 'Unexpected archive directory.'}
   continue
  }
  if($entries.ContainsKey($entry.FullName)){throw 'Duplicate/case-colliding ZIP entry.'}
  $entries[$entry.FullName]=$entry
 }
 Assert-QvvrEntryNames @($entries.Keys) $expected
 function Read-ArchiveText([string]$Name){
  $reader=[IO.StreamReader]::new($entries[$Name].Open())
  try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
 }
 $hashes=@{}
 foreach($name in $entries.Keys){
  $stream=$entries[$name].Open();$sha=[Security.Cryptography.SHA256]::Create()
  try{$hashes[$name]=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$stream.Dispose()}
 }
 foreach($file in $inputs.GetEnumerator()){
  if($hashes[$file.Key] -ne (Get-FileHash -LiteralPath $file.Value -Algorithm SHA256).Hash.ToLowerInvariant()){throw "Archive input differs: $($file.Key)"}
 }
 $listed=@{}
 foreach($line in (Read-ArchiveText 'qvvr-files.sha256') -split '\r?\n'){
  if(!$line){continue}
  if($line -cnotmatch '^([0-9a-f]{64})  (.+)$'){throw 'Malformed file checksum manifest.'}
  $digest=$Matches[1];$name=$Matches[2]
  if($listed.ContainsKey($name) -or $name -eq 'qvvr-files.sha256' -or !$hashes.ContainsKey($name) -or $hashes[$name] -ne $digest){throw 'File checksum verification failed.'}
  $listed[$name]=$true
 }
 if($listed.Count -ne $entries.Count-1){throw 'File checksum manifest incomplete.'}
 $manifest=Read-ArchiveText 'qvvr-package.json' | ConvertFrom-Json
 $source=Get-Content (Join-Path $root 'src/QVVR/Plugin.cs') -Raw
 $version=[regex]::Match($source,'public const string Version = "([0-9]+\.[0-9]+\.[0-9]+)";').Groups[1].Value
 if($manifest.version -ne $version -or $manifest.name -ne 'QVVR' -or $manifest.steamAppId -ne 1494110 -or $manifest.architecture -ne 'win-x64' -or $manifest.releaseStatus -ne 'candidate-pending-headset-qa' -or $manifest.experimental -ne $true){throw 'Invalid release metadata.'}
 if($manifest.sourceCommit -notmatch '^[0-9a-f]{40}$' -or $manifest.sourceDirty -isnot [bool]){throw 'Source provenance missing.'}
 if([Reflection.AssemblyName]::GetAssemblyName($inputs['BepInEx/plugins/QVVR/QVVR.dll']).Version.ToString() -ne "$version.0"){throw 'Managed binary version differs from release version.'}
 if((Read-ArchiveText '.qvvr-loader-owner').Trim() -ne "QVVR $version installed BepInEx 5.4.23.5"){throw 'Ownership marker missing/stale.'}
 if((Read-ArchiveText '.doorstop_version').Trim() -ne '4.5.0'){throw 'Unexpected Doorstop version.'}
 $config=Read-ArchiveText 'BepInEx/config/dev.qvvr.prototype.cfg'
 if($config -notmatch '(?m)^PlacementSaved = false\r?$' -or $config -notmatch '(?m)^Passthrough = false\r?$'){throw 'Release must use the clean unsaved, desktop-safe config template.'}
 # Our text only: upstream license/source copyright notices are retained verbatim.
 foreach($name in @('README.txt','RELEASE-NOTES.txt','qvvr-package.json','BepInEx/config/dev.qvvr.prototype.cfg')){
  $text=Read-ArchiveText $name
  if($text -match '(?i)([a-z]:[\\/]Users[\\/](?!Public\b)|\bgh[pousr]_[a-z0-9]{20,}|\bgithub_pat_[a-z0-9_]{20,}|-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----)'){throw "Private data pattern in archive text: $name"}
 }
 $zipHash=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
 $expectedHashLine=$zipHash+'  '+[IO.Path]::GetFileName($ZipPath)
 if((Get-Content -LiteralPath "$ZipPath.sha256" -Raw).Trim() -cne $expectedHashLine){throw 'ZIP checksum sidecar mismatch.'}
}finally{$archive.Dispose()}
Write-Host "Package audit passed: $($expected.Count) exact files, original input hashes, complete licenses/source, clean config, metadata and SHA-256 manifests. Not headset validation or a publisher signature."

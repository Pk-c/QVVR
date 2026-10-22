[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'src/QVVR/Plugin.cs') -Raw), 'public const string Version = "([0-9]+\.[0-9]+\.[0-9]+)";')
if (-not $versionMatch.Success) { throw 'Cannot determine the plugin release version.' }
$version = $versionMatch.Groups[1].Value
$releaseRoot = Join-Path $root 'build\release'
$stage = Join-Path $releaseRoot "QVVR-v$version"
$zip = Join-Path $releaseRoot "QVVR-v$version.zip"
$hashFile = "$zip.sha256"
. (Join-Path $PSScriptRoot 'package-layout.ps1')
& (Join-Path $PSScriptRoot 'setup-release-deps.ps1') -Offline
$packageFiles = Get-QvvrPackageFiles $root $Configuration

foreach ($required in $packageFiles.Values) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required package input missing: $required"
    }
}

$resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
$resolvedStage = [IO.Path]::GetFullPath($stage)
if (-not $resolvedStage.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace staging path outside project: $resolvedStage"
}

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'BepInEx\plugins\QVVR') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'BepInEx\config') | Out-Null

foreach ($file in $packageFiles.GetEnumerator()) {
    $destination = Join-Path $stage $file.Key
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.Value -Destination $destination
}
Set-Content -LiteralPath (Join-Path $stage '.qvvr-loader-owner') -Value "QVVR $version installed BepInEx 5.4.23.5" -Encoding Ascii

$sourceCommit = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot record source revision.' }
$sourceDirty = @(& git -C $root status --porcelain).Count -gt 0
if ($LASTEXITCODE -ne 0) { throw 'Cannot record source worktree status.' }

$manifest = [ordered]@{
    name = 'QVVR'
    version = $version
    steamAppId = 1494110
    createdUtc = [DateTime]::UtcNow.ToString('o')
    releaseStatus = 'candidate-pending-headset-qa'
    sourceCommit = $sourceCommit
    sourceDirty = $sourceDirty
    backend = 'Exclusive-OpenXR-with-OpenVR-fallback'
    passthrough = 'OpenXR-ALPHA_BLEND-opt-in'
    clipping = 'D3D11-global-fragment-cylinder'
    controls = 'two-hand-natural-placement'
    layout = 'persistent-physical-entry-fit'
    experimental = $true
    architecture = 'win-x64'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'qvvr-package.json') -Encoding UTF8

$fileHashes = foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse -Force | Sort-Object FullName) {
    $relative = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\','/')
    (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relative
}
$fileHashes | Set-Content -LiteralPath (Join-Path $stage 'qvvr-files.sha256') -Encoding Ascii

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = Get-FileHash -LiteralPath $zip -Algorithm SHA256
Set-Content -LiteralPath $hashFile -Value ($hash.Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip)) -Encoding Ascii
& (Join-Path $PSScriptRoot 'test-package.ps1') -ZipPath $zip -Configuration $Configuration

# Portable PC-side USB manager is separate: never put ADB or management tools
# into the game's mod overlay. Extract this small tools ZIP beside the mod ZIP.
$frameZip=Join-Path $releaseRoot 'QVVR-Frame-Setup.zip'
if(Test-Path -LiteralPath $frameZip){Remove-Item -LiteralPath $frameZip}
$frameArchive=[IO.Compression.ZipFile]::Open($frameZip,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($file in (Get-QvvrFrameToolFiles $root).GetEnumerator()){
  Copy-Item -LiteralPath $file.Value -Destination (Join-Path $releaseRoot $file.Key)
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($frameArchive,$file.Value,$file.Key,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
 }
}finally{$frameArchive.Dispose()}
$frameHash=(Get-FileHash -LiteralPath $frameZip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$frameZip.sha256" -Value ($frameHash+'  '+[IO.Path]::GetFileName($frameZip)) -Encoding Ascii

Write-Host "Package tree: $stage"
Write-Host "Archive:      $zip"
Write-Host "SHA-256:      $($hash.Hash.ToLowerInvariant())"
Write-Host "Frame tools:  $frameZip (also available unpacked beside it)"

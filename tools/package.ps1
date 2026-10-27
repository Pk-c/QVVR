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
# Single release ZIP: PC/ is the game overlay copied beside QV.exe; SteamFrame/
# holds the USB installer, which uploads only PC/ content. No ADB is bundled.
$overlay = Join-Path $stage 'PC'
New-Item -ItemType Directory -Force -Path (Join-Path $overlay 'BepInEx\plugins\QVVR') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $overlay 'BepInEx\config') | Out-Null

foreach ($file in $packageFiles.GetEnumerator()) {
    $destination = Join-Path $overlay $file.Key
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.Value -Destination $destination
}
Set-Content -LiteralPath (Join-Path $overlay '.qvvr-loader-owner') -Value "QVVR $version installed BepInEx 5.4.23.5" -Encoding Ascii

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
    diagnostics = $Configuration -ne 'Release'
    backend = 'Exclusive-OpenXR-with-OpenVR-fallback'
    passthrough = 'OpenXR-ALPHA_BLEND-opt-in'
    clipping = 'D3D11-global-fragment-cylinder'
    controls = 'two-hand-natural-placement'
    layout = 'persistent-physical-entry-fit'
    experimental = $true
    architecture = 'win-x64'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $overlay 'qvvr-package.json') -Encoding UTF8

$overlayFull = (Get-Item -LiteralPath $overlay).FullName.TrimEnd('\')
$fileHashes = foreach ($file in Get-ChildItem -LiteralPath $overlayFull -File -Recurse -Force | Sort-Object FullName) {
    $relative = $file.FullName.Substring($overlayFull.Length + 1).Replace('\','/')
    (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $relative
}
$fileHashes | Set-Content -LiteralPath (Join-Path $overlay 'qvvr-files.sha256') -Encoding Ascii

foreach ($file in (Get-QvvrReleaseExtraFiles $root).GetEnumerator()) {
    $destination = Join-Path $stage $file.Key
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.Value -Destination $destination
}

# Outputs of the former two-ZIP layout would only cause confusion.
foreach ($stale in @('QVVR-Frame-Setup.zip','QVVR-Frame-Setup.zip.sha256','QVVR-Frame-Setup.bat','QVVR-Frame-Setup.ps1','QVVR-Frame-Setup.txt')) {
    $stalePath = Join-Path $releaseRoot $stale
    if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force }
}

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
# Explicit entries: .NET Framework's CreateFromDirectory writes '\' separators.
$stageFull = (Get-Item -LiteralPath $stage).FullName.TrimEnd('\')
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $stageFull -File -Recurse -Force | Sort-Object FullName) {
        $entryName = $file.FullName.Substring($stageFull.Length + 1).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
$hash = Get-FileHash -LiteralPath $zip -Algorithm SHA256
Set-Content -LiteralPath $hashFile -Value ($hash.Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip)) -Encoding Ascii
& (Join-Path $PSScriptRoot 'test-package.ps1') -ZipPath $zip -Configuration $Configuration

Write-Host "Release tree: $stage (PC/ overlay, SteamFrame/ USB installer)"
Write-Host "Archive:      $zip"
Write-Host "SHA-256:      $($hash.Hash.ToLowerInvariant())"

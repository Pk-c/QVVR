[CmdletBinding()]
param([ValidateSet('Staged','WorkingTree')][string]$Mode='Staged')
$ErrorActionPreference = 'Stop'
$qvPublicationRoot = Split-Path -Parent $PSScriptRoot
if ($Mode -eq 'Staged') {
    $qvPublicationFiles = @(& git -C $qvPublicationRoot -c core.quotepath=false diff --cached --name-only --diff-filter=ACMR)
} else {
    $qvPublicationFiles = @(& git -C $qvPublicationRoot -c core.quotepath=false ls-files --cached --others --exclude-standard --deduplicate)
}
if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate publication files.' }
if ($qvPublicationFiles.Count -eq 0) { throw 'No files to audit.' }
$qvAllowed = @(
    '^(README\.md|AGENTS\.md|LICENSE|QVVR\.slnx|\.gitignore|\.gitattributes)$',
    '^docs/(architecture|testing|repository-safety|release)\.md$',
    '^src/(QVVR|QVVR\.Native)/(?!.*(?:^|/)(?:bin|obj|obj-direct)/).+\.(cs|csproj|cpp|h)$',
    '^src/QVVR\.Native/CMakeLists\.txt$',
    '^tools/[A-Za-z0-9_-]+\.(ps1|py|cpp)$',
    '^tools/performance-fixture\.cs$',
    '^package-assets/(README\.txt|RELEASE-NOTES\.txt|QVVR-THIRD-PARTY-NOTICES\.txt|qvvr-launch-options\.txt|dev\.qvvr\.prototype\.cfg|uninstall\.(bat|ps1)|QVVR-Frame-Setup\.(bat|ps1|txt)|RELEASE-README\.txt)$'
)
$qvChecks = [ordered]@{
    'private home path' = '(?i)(?:[a-z]:[\\/]Users[\\/](?!Public\b)[^\\/\s]+|[/]home[/](?!steamos(?:[/]|\b))[^/\s]+)'
    'e-mail address' = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    'access token' = '(?i)\b(?:gh[pousr]_[a-z0-9]{20,}|github_pat_[a-z0-9_]{20,}|AKIA[A-Z0-9]{16})\b'
    'private key' = '-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----'
    'authenticated URL' = 'https?://[^/\s:@"'']+:[^/\s@"'']+@'
    'embedded credential' = '(?i)(?:password|passwd|client_secret|api[_-]?key|access[_-]?token)\s*[:=]\s*["''][A-Z0-9+/=_-]{12,}["'']'
    'non-text control content' = '[\x00-\x08\x0b\x0c\x0e-\x1f\ufffd]'
    'untranslated UI text' = '\b(?:REGLAGES|Recentrer|Inclinaison|Echelle|Masques|Fluide|Equilibre|redemarrage)\b'
}
$qvFailures = @()
foreach ($qvPublicationFile in $qvPublicationFiles) {
    if (-not ($qvAllowed | Where-Object { $qvPublicationFile -match $_ })) {
        $qvFailures += "Disallowed path/type: $qvPublicationFile"
        continue
    }
    if ($Mode -eq 'Staged') {
        $qvBytes = & git -C $qvPublicationRoot cat-file -s ":$qvPublicationFile"
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect staged file: $qvPublicationFile" }
        if ([long]$qvBytes -gt 1048576) { $qvFailures += "Oversized source file: $qvPublicationFile"; continue }
        $qvText = (& git -C $qvPublicationRoot show ":$qvPublicationFile") -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Cannot read staged file: $qvPublicationFile" }
    } else {
        $qvPath = Join-Path $qvPublicationRoot $qvPublicationFile
        if (-not (Test-Path -LiteralPath $qvPath -PathType Leaf)) { continue } # Local deletion.
        if ((Get-Item -LiteralPath $qvPath).Length -gt 1048576) { $qvFailures += "Oversized source file: $qvPublicationFile"; continue }
        $qvText = Get-Content -LiteralPath $qvPath -Raw
    }
    foreach ($qvCheck in $qvChecks.GetEnumerator()) {
        # The language rule targets runtime strings, not this rule's vocabulary.
        if ($qvCheck.Key -eq 'untranslated UI text' -and $qvPublicationFile -notlike 'src/*' -and $qvPublicationFile -ne 'package-assets/README.txt') { continue }
        # Do not print matching text: findings themselves must not leak secrets.
        if ($qvText -match $qvCheck.Value) { $qvFailures += "$($qvCheck.Key): $qvPublicationFile" }
    }
}
if ($qvFailures.Count) { throw ("Publication audit failed:`n" + ($qvFailures -join "`n")) }
Write-Host "Publication audit passed: $($qvPublicationFiles.Count) $Mode text files. No files staged or published; review the staged diff before pushing."

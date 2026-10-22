[CmdletBinding()]
param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$reportDirectory=Join-Path $root ('artifacts/release-verification-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
New-Item -ItemType Directory -Path $reportDirectory | Out-Null
$results=[Collections.Generic.List[object]]::new()
function Invoke-ReleaseCheck([string]$Name,[string[]]$Arguments){
 $started=[DateTime]::UtcNow
 Write-Host "Checking $Name..."
 $output=@(& pwsh -NoProfile -File (Join-Path $PSScriptRoot $Name) @Arguments 2>&1)
 $exitCode=$LASTEXITCODE
 $output | Out-File -LiteralPath (Join-Path $reportDirectory "$Name.log") -Encoding utf8
 $results.Add([ordered]@{name=$Name;exitCode=$exitCode;seconds=([DateTime]::UtcNow-$started).TotalSeconds})
 $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $reportDirectory 'results.json') -Encoding utf8
 if($exitCode -ne 0){throw "Release check failed: $Name. Inspect the private local report: $reportDirectory"}
 Write-Host "Passed $Name"
}
Invoke-ReleaseCheck 'check-publication.ps1' @('-Mode','WorkingTree')
if(!$SkipBuild){Invoke-ReleaseCheck 'build.ps1' @()}
foreach($test in Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'test-*.ps1' -File | Sort-Object Name){Invoke-ReleaseCheck $test.Name @()}
Write-Host "Automated release checks passed: $($results.Count). Private report: $reportDirectory"
Write-Host 'Candidate only: Frame visual/performance gates remain. Nothing staged, committed, tagged, deployed, launched or published.'

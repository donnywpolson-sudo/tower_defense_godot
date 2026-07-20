param()

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo
$config = Read-WorkflowConfig
$resilience = Get-ObjectProperty -Object $config -Name 'simulationResilience' -Default $null
if ($null -eq $resilience -or $null -ne $resilience.PSObject.Properties['lightFallback']) {
    throw 'Workflow resilience must use retry-only behavior; mixed-packet fallback is not allowed.'
}
if (-not [bool](Get-ObjectProperty -Object $config -Name 'reportFirstDefault' -Default $false)) {
    throw 'Report-first default is not enabled.'
}

$validationRoot = Join-Path $repoRoot 'logs\godot\ai_simulation\resilience_validation'
if (-not (Test-Path -LiteralPath $validationRoot)) {
    New-Item -ItemType Directory -Path $validationRoot | Out-Null
}
$shell = (Get-Command powershell.exe -ErrorAction Stop).Source
$attemptResults = New-Object System.Collections.Generic.List[object]
for ($attemptIndex = 1; $attemptIndex -le 2; $attemptIndex++) {
    $attemptLabel = "attempt_$attemptIndex"
    $command = if ($attemptIndex -eq 1) { 'exit 7' } else { 'Write-Output retry_success; exit 0' }
    $attemptResult = Invoke-RepoProcess `
        -Label "resilience $attemptLabel" `
        -FilePath $shell `
        -ArgumentList @('-NoProfile', '-Command', $command) `
        -WorkingDirectory $repoRoot `
        -StdoutPath (Join-Path $validationRoot "${attemptLabel}_stdout.log") `
        -StderrPath (Join-Path $validationRoot "${attemptLabel}_stderr.log") `
        -TimeoutSeconds 30 `
        -ReturnResult
    $attemptResults.Add($attemptResult)
}
if (@($attemptResults.ToArray()).Count -ne 2 -or $attemptResults[0].succeeded -or -not $attemptResults[1].succeeded) {
    throw 'Retry-only process resilience contract failed.'
}
foreach ($path in @(
    (Join-Path $validationRoot 'attempt_1_stdout.log'),
    (Join-Path $validationRoot 'attempt_1_stderr.log'),
    (Join-Path $validationRoot 'attempt_2_stdout.log'),
    (Join-Path $validationRoot 'attempt_2_stderr.log')
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Expected per-attempt log was not written: $path"
    }
}
Write-Host 'RESILIENCE_PROCESS_VALIDATION_OK'
Write-Host 'RESILIENCE_REPORT_FIRST_CONTRACT_OK'

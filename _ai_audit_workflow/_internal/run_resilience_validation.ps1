param()

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo
$validationRoot = Join-Path $repoRoot 'logs\godot\ai_simulation\resilience_validation'
if (-not (Test-Path -LiteralPath $validationRoot)) {
    New-Item -ItemType Directory -Path $validationRoot | Out-Null
}

$shell = (Get-Command powershell.exe -ErrorAction Stop).Source
$attemptResults = New-Object System.Collections.Generic.List[object]
for ($attemptIndex = 1; $attemptIndex -le 2; $attemptIndex++) {
    $attemptLabel = "attempt_$attemptIndex"
    $command = if ($attemptIndex -eq 1) { 'Start-Sleep -Seconds 2; exit 7' } else { 'Write-Output retry_success; exit 0' }
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
    if ($attemptResult.succeeded) {
        break
    }
}

if (@($attemptResults.ToArray()).Count -ne 2) {
    throw "Expected exactly one retry, got $(@($attemptResults.ToArray()).Count) process attempt(s)."
}
$failed = $attemptResults[0]
$succeeded = $attemptResults[1]
if ($failed.succeeded -or [int]$failed.exitCode -eq 0) {
    throw 'Forced failure process unexpectedly succeeded.'
}
if (-not $succeeded.succeeded) {
    throw "Retry success process failed with exit code $($succeeded.exitCode)."
}
if (@($failed.diagnostics).Count -eq 0 -or $null -eq $failed.PSObject.Properties['maxWorkingSetBytes']) {
    throw 'Structured process diagnostics were not returned.'
}
$diagnostic = @($failed.diagnostics) | Select-Object -First 1
foreach ($propertyName in @('pid', 'alive', 'workingSetBytes', 'privateMemoryBytes', 'cpuSeconds')) {
    if ($null -eq $diagnostic.PSObject.Properties[$propertyName]) {
        throw "Process diagnostic field is missing: $propertyName"
    }
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

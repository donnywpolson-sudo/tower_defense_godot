param([switch] $SkipProductionFallback)

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

$config = Read-WorkflowConfig
$validationScriptRoot = Join-Path $repoRoot 'logs\godot\ai_simulation\resilience_validation'
$realLauncher = Join-Path $repoRoot $config.launcher

function New-FailureLauncherShim {
    param([Parameter(Mandatory)][string] $Name, [bool] $FailChunks)
    $shimPath = Join-Path $validationScriptRoot "$Name.cmd"
    $failChunksFlag = if ($FailChunks) { '1' } else { '0' }
    @"
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "IS_FULL=0"
set "IS_CHUNK=0"
set "IS_AGGREGATE=0"
set "FAIL_CHUNKS=$failChunksFlag"
echo(%*| findstr /C:"--runs=240" >nul && set "IS_FULL=1"
echo(%*| findstr /C:"--runs=120" >nul && set "IS_CHUNK=1"
echo(%*| findstr /C:"--aggregate-metadata-file" >nul && set "IS_AGGREGATE=1"
if "!IS_FULL!"=="1" if "!IS_AGGREGATE!"=="1" goto delegate
if "!IS_FULL!"=="1" (
    echo TEST_FORCED_FULL_FAILURE 1>&2
    exit /b 17
)
if "!FAIL_CHUNKS!"=="1" if "!IS_CHUNK!"=="1" (
    echo TEST_FORCED_CHUNK_FAILURE 1>&2
    exit /b 19
)
:delegate
call "$realLauncher" %*
exit /b !ERRORLEVEL!
"@ | Set-Content -LiteralPath $shimPath -Encoding ASCII
    return $shimPath
}

function Invoke-TestPowerShellScript {
    param(
        [Parameter(Mandatory)][string] $ScriptPath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $OutputPath
    )
    $errorPath = [System.IO.Path]::ChangeExtension($OutputPath, '.stderr.log')
    return Invoke-RepoProcess `
        -Label "resilience harness $([System.IO.Path]::GetFileName($ScriptPath))" `
        -FilePath $shell `
        -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + @($Arguments)) `
        -WorkingDirectory $repoRoot `
        -StdoutPath $OutputPath `
        -StderrPath $errorPath `
        -TimeoutSeconds 900 `
        -MirrorRunProgress `
        -ReturnResult
}

function Read-WorkflowFindings {
    $findingsPath = Join-Path (Join-Path $repoRoot $config.currentDir) 'findings.json'
    return Get-Content -Raw -LiteralPath $findingsPath | ConvertFrom-Json
}

$deepAuditPath = Join-Path $PSScriptRoot 'run_deep_audit.ps1'
if (-not $SkipProductionFallback) {
$fallbackShim = New-FailureLauncherShim -Name 'fail_full_only_launcher' -FailChunks:$false
$fallbackRunLog = Join-Path $validationScriptRoot 'fallback_end_to_end.log'
$fallbackResult = Invoke-TestPowerShellScript -ScriptPath $deepAuditPath -Arguments @('-Tier', 'Light', '-SkipValidations', '-SkipPlayableSurface', '-SimulationLauncherOverride', $fallbackShim) -OutputPath $fallbackRunLog
if (-not $fallbackResult.succeeded) {
    throw "Production-faithful fallback audit failed with exit code $($fallbackResult.exitCode). See $fallbackRunLog"
}
$fallbackState = Read-WorkflowFindings
if ([string]$fallbackState.status -ne 'pass with gaps' -or [string]$fallbackState.simulation.mode -ne 'chunked_fallback') {
    throw "Fallback audit did not record pass with gaps/chunked_fallback: status=$($fallbackState.status), mode=$($fallbackState.simulation.mode)."
}
$aggregateReportPath = [string]$fallbackState.artifacts.simulationPacket.json
$aggregateReport = Get-Content -Raw -LiteralPath $aggregateReportPath | ConvertFrom-Json
$runIds = @($aggregateReport.runs | ForEach-Object { [int]$_.run_id })
if ([int]$aggregateReport.config.runs -ne 240 -or [int]$aggregateReport.summary.total_runs -ne 240 -or $runIds.Count -ne 240 -or @($runIds | Sort-Object -Unique).Count -ne 240 -or ($runIds | Measure-Object -Minimum).Minimum -ne 1 -or ($runIds | Measure-Object -Maximum).Maximum -ne 240) {
    throw 'Fallback aggregate did not produce exactly 240 unique runs covering IDs 1-240.'
}
if ([string]$aggregateReport.aggregation.mode -ne 'chunked_fallback' -or [string]$aggregateReport.aggregation.fallback_status -ne 'completed' -or (@($aggregateReport.aggregation.chunk_runs) -join ',') -ne '120,120' -or @($aggregateReport.aggregation.source_reports).Count -ne 2 -or @($aggregateReport.aggregation.attempt_history).Count -ne 5) {
    throw 'Fallback aggregate metadata is incomplete.'
}
if ($null -eq $aggregateReport.wave_metrics -or $aggregateReport.config.scenario_probe_mode -ne 'smoke') {
    throw 'Fallback aggregate did not recompute metrics and scenario probes.'
}
foreach ($attempt in @($fallbackState.simulation.attempts)) {
    foreach ($artifactPath in @($attempt.stdoutPath, $attempt.stderrPath, $attempt.engineStderrPath)) {
        if (-not (Test-Path -LiteralPath ([string]$artifactPath))) {
            throw "Expected root-level attempt artifact is missing: $artifactPath"
        }
    }
}
Write-Host 'RESILIENCE_FALLBACK_END_TO_END_OK'
}

$allFailureShim = New-FailureLauncherShim -Name 'fail_full_and_chunk_launcher' -FailChunks:$true
$cyclePath = Join-Path $PSScriptRoot 'run_cycle.ps1'
$failureRunLog = Join-Path $validationScriptRoot 'unrecoverable_failure.log'
$failureResult = Invoke-TestPowerShellScript -ScriptPath $cyclePath -Arguments @('-Tier', 'Light', '-SimulationLauncherOverride', $allFailureShim) -OutputPath $failureRunLog
$failureState = Read-WorkflowFindings
$queuePath = Join-Path (Join-Path $repoRoot $config.currentDir) 'improvement_queue.json'
$failureQueue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
if ([string]$failureState.status -ne 'fail' -or [string]$failureState.simulation.mode -ne 'unrecoverable_failure' -or $failureQueue.invalidated -ne $true -or [int]$failureQueue.count -ne 0 -or @($failureQueue.items | Where-Object { $_.status -eq 'queued' }).Count -ne 0) {
    throw 'Unrecoverable failure did not leave an invalidated, non-applyable queue.'
}
$failureOutput = (Get-Content -Raw -LiteralPath $failureRunLog) + (Get-Content -Raw -LiteralPath ([System.IO.Path]::ChangeExtension($failureRunLog, '.stderr.log')))
if ($failureOutput -notmatch '(?im)^fail\s*$' -or $failureOutput -match 'build_improvement_queue|run_improvement_pass|RunCodex|Codex') {
    throw 'Unrecoverable failure path reached queue building or Codex execution.'
}
Write-Host 'RESILIENCE_UNRECOVERABLE_GATE_OK'

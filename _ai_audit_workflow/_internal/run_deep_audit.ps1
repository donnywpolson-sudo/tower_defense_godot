param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $SkipSimulation,
    [switch] $SkipValidations,
    [switch] $SkipPlayableSurface,
    [string] $SimulationLauncherOverride = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$startedAt = Get-Date
$runId = Get-Date -Format 'yyyy_MM_dd_HHmmss'
$simulationStartedAt = $startedAt
$visualStartedAt = [datetime]::MinValue
$checks = New-Object System.Collections.Generic.List[object]
$findings = New-Object System.Collections.Generic.List[object]
$gaps = New-Object System.Collections.Generic.List[object]
$validationResults = New-Object System.Collections.Generic.List[object]
$simulationAttempts = New-Object System.Collections.Generic.List[object]
$simulationMode = 'not_run'
$packet = $null
$finalStatus = 'pass'
$failureMessage = ''
$preExistingGodotProcessIds = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*Godot*' } | Select-Object -ExpandProperty Id)

function Add-Check {
    param([string] $Name, [string] $Status, [string] $Detail)
    $script:checks.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail })
}

function Add-Finding {
    param(
        [string] $Id,
        [string] $Area,
        [int] $Score,
        [string] $Title,
        [string] $Classification,
        [string] $Evidence,
        [string] $Action,
        [bool] $EvidenceBacked,
        [bool] $EligibleForFix
    )
    $script:findings.Add([pscustomobject]@{
        id = $Id
        area = $Area
        score = $Score
        title = $Title
        classification = $Classification
        evidence = $Evidence
        recommendedAction = $Action
        evidenceBacked = $EvidenceBacked
        eligibleForFix = $EligibleForFix
        status = 'open'
    })
}

function Add-Gap {
    param([string] $Area, [string] $Detail, [string] $RecommendedEvidence)
    $script:gaps.Add([pscustomobject]@{ area = $Area; detail = $Detail; recommendedEvidence = $RecommendedEvidence })
}

function Stop-NewGodotProcesses {
    param([int[]] $PreExistingIds)
    $current = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*Godot*' })
    foreach ($process in $current) {
        if ($PreExistingIds -notcontains [int]$process.Id) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            } catch {
            }
        }
    }
}

function Get-ReportText {
    $path = Join-Path $repoRoot $config.auditReport
    if (Test-Path -LiteralPath $path) {
        return Get-Content -Raw -LiteralPath $path
    }
    return ''
}

function Test-ValidationPassed {
    param([Parameter(Mandatory)][string] $Name)
    foreach ($result in $script:validationResults) {
        if ([string]$result.name -eq $Name -and [string]$result.status -eq 'passed') {
            return $true
        }
    }
    foreach ($validation in $config.validations) {
        if ([string]$validation.name -eq $Name) {
            $logPath = Join-Path $repoRoot ([string]$validation.log)
            $expected = [string]$validation.expected
            if ((Test-Path -LiteralPath $logPath) -and (Get-Content -Raw -LiteralPath $logPath).Contains($expected)) {
                return $true
            }
        }
    }
    return $false
}

function Test-ValidationLogContains {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Pattern
    )
    foreach ($validation in $config.validations) {
        if ([string]$validation.name -eq $Name) {
            $logPath = Join-Path $repoRoot ([string]$validation.log)
            if (-not (Test-Path -LiteralPath $logPath)) {
                return $false
            }
            return ((Get-Content -Raw -LiteralPath $logPath) -match $Pattern)
        }
    }
    return $false
}

function Add-ReportDerivedFindings {
    param([string] $ReportText)
    if ($ReportText.Trim().Length -eq 0) {
        Add-Gap -Area 'Audit report' -Detail "Root audit report is missing: $($config.auditReport)" -RecommendedEvidence 'Run a bounded audit or restore the report.'
        return
    }

    if (($ReportText -match 'Prompt metadata validator fails' -or $ReportText -match 'AI_PROMPT_METADATA_VALIDATION_FAILED') -and -not (Test-ValidationPassed -Name 'ai_prompt_metadata_validation')) {
        Add-Finding -Id 'report-prompt-metadata-validator' -Area 'Audit validation' -Score 55 -Title 'Prompt metadata validator/report contract mismatch is recorded in the current audit report' -Classification 'partially proven' -Evidence "$($config.auditReport) records AI_PROMPT_METADATA_VALIDATION_FAILED / prompt metadata label drift." -Action 'Inspect the prompt metadata validator and generated report strings, then fix only the verified contract mismatch.' -EvidenceBacked $true -EligibleForFix $true
    }
}

function Add-SimulationDerivedFindings {
    param($Packet)
    if ($null -eq $Packet -or -not $Packet.complete) {
        Add-Gap -Area 'AI simulation packet' -Detail 'No complete AI simulation packet was available for this workflow state.' -RecommendedEvidence 'Run Light or Deep audit to produce a fresh packet.'
        return
    }

    $json = Read-JsonFileOrNull -Path $Packet.json.FullName
    if ($null -eq $json) {
        Add-Gap -Area 'AI simulation packet' -Detail "Latest packet JSON could not be parsed: $($Packet.json.FullName)" -RecommendedEvidence 'Run a fresh bounded simulation.'
        return
    }
    $summary = Get-ObjectProperty -Object $json -Name 'summary'
    $issueCounts = Get-ObjectProperty -Object $summary -Name 'issue_counts' -Default @{}
    $severityCounts = Get-ObjectProperty -Object $summary -Name 'severity_counts' -Default @{}
    $bugCount = [int](Get-ObjectProperty -Object $issueCounts -Name 'bug' -Default 0)
    $validationCount = [int](Get-ObjectProperty -Object $issueCounts -Name 'validation' -Default 0)
    $highSeverity = [int](Get-ObjectProperty -Object $severityCounts -Name 'high' -Default 0)
    if ($bugCount -gt 0 -or $validationCount -gt 0 -or $highSeverity -gt 0) {
        Add-Finding -Id 'simulation-runtime-or-validation-issues' -Area 'Runtime / validation' -Score 45 -Title 'Latest AI simulation packet reports implementation-relevant issue counts' -Classification 'partially proven' -Evidence "Packet $($Packet.json.FullName) has bug=$bugCount, validation=$validationCount, high severity=$highSeverity." -Action 'Inspect exact issue rows in the latest packet and fix only the smallest verified runtime or validation defect.' -EvidenceBacked $true -EligibleForFix $true
    }
}

function Add-CurrentCoverageGaps {
    param($VisualEvidence)
    if (-not (Test-ValidationPassed -Name 'playable_surface_validation') -or [int](Get-ObjectProperty -Object $VisualEvidence -Name 'count' -Default 0) -eq 0) {
        Add-Gap -Area 'Manual play proxy' -Detail 'Scene/input and screenshot evidence were not produced in this workflow state.' -RecommendedEvidence 'Run playable-surface validation in a rendering-capable Godot session.'
    }
    if (-not (Test-ValidationPassed -Name 'asset_audio_validation')) {
        Add-Gap -Area 'Audio' -Detail 'Asset/audio load and fallback behavior were not proven by the current validation matrix.' -RecommendedEvidence 'Run asset/audio validation.'
    }
    if (-not (Test-ValidationPassed -Name 'export_platform_validation')) {
        Add-Gap -Area 'Export/platform readiness' -Detail 'Project export/platform readiness settings were not proven by the current validation matrix.' -RecommendedEvidence 'Run export/platform validation.'
    }
    if ((Test-ValidationPassed -Name 'playable_surface_validation') -and (Test-ValidationLogContains -Name 'playable_surface_validation' -Pattern 'ObjectDB instances were leaked|resources still in use')) {
        Add-Finding -Id 'review-playable-surface-cleanup-warning' -Area 'Scene/resource cleanup' -Score 70 -Title 'Playable-surface validation reported shutdown cleanup warnings' -Classification 'partially proven' -Evidence 'Current playable-surface validation log records shutdown cleanup warnings.' -Action 'Reproduce the cleanup warning in a narrow validation before changing resource lifecycle code.' -EvidenceBacked $false -EligibleForFix $false
    }
}

function Invoke-Validation {
    param($Validation)
    $scriptPath = [string]$Validation.script
    $logPath = Join-Path $repoRoot ([string]$Validation.log)
    $expected = [string]$Validation.expected
    $headless = [bool](Get-ObjectProperty -Object $Validation -Name 'headless' -Default $true)
    $scriptLocal = Join-Path $repoRoot ($scriptPath -replace '^res://', '' -replace '/', '\')
    if (-not (Test-Path -LiteralPath $scriptLocal)) {
        throw "Validation script is missing: $scriptPath"
    }
    $logDir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    $args = New-Object System.Collections.Generic.List[string]
    if ($headless) {
        $args.Add('--headless')
    }
    $args.Add('--log-file')
    $args.Add($logPath)
    $args.Add('--path')
    $args.Add($repoRoot)
    $args.Add('--script')
    $args.Add($scriptPath)
    Invoke-RepoProcess -Label "validation $($Validation.name)" -FilePath $config.godotExe -ArgumentList @($args.ToArray()) -WorkingDirectory $repoRoot -TimeoutSeconds 900
    $token = Test-GodotLogExpectedToken -LogPath $logPath -Expected $expected
    if (-not [bool]$token.passed) {
        throw "Validation $($Validation.name) exited 0 but did not write expected token. $($token.detail)"
    }
    $script:validationResults.Add([pscustomobject]@{ name = $Validation.name; status = 'passed'; log = [string]$Validation.log; expected = $expected })
}

function Invoke-SimulationAttempt {
    param(
        [Parameter(Mandatory)][string] $LauncherPath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $AttemptLabel,
        [Parameter(Mandatory)][int] $TimeoutSeconds
    )
    $attemptRoot = Join-Path (Join-Path $repoRoot 'logs\godot\ai_simulation') $runId
    $attemptDir = Join-Path $attemptRoot $AttemptLabel
    $launcherLogDir = Join-Path $attemptDir 'launcher'
    if (-not (Test-Path -LiteralPath $launcherLogDir)) {
        New-Item -ItemType Directory -Path $launcherLogDir | Out-Null
    }
    $stdoutPath = Join-Path $attemptRoot ("{0}_stdout.log" -f $AttemptLabel)
    $stderrPath = Join-Path $attemptRoot ("{0}_stderr.log" -f $AttemptLabel)
    $engineStderrPath = Join-Path $attemptRoot ("{0}_engine_stderr.log" -f $AttemptLabel)
    [System.IO.File]::WriteAllText($engineStderrPath, '')
    $attemptArgs = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $Arguments) {
        $attemptArgs.Add([string]$argument)
    }
    $startedAt = Get-Date
    try {
        $result = Invoke-RepoProcess -Label "$Tier simulation $AttemptLabel" -FilePath $LauncherPath -ArgumentList @($attemptArgs.ToArray()) -WorkingDirectory $repoRoot -TimeoutSeconds $TimeoutSeconds -StdoutPath $stdoutPath -StderrPath $stderrPath -EnvironmentVariables @{ TD_SIM_LOG_DIR = $launcherLogDir; TD_SIM_ENGINE_STDERR_PATH = $engineStderrPath } -MirrorRunProgress -ReturnResult
    } catch {
        $result = [pscustomobject]@{
            succeeded = $false
            exitCode = -1
            timedOut = $false
            durationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
            processId = $null
            diagnostics = @()
            maxWorkingSetBytes = 0
            maxPrivateMemoryBytes = 0
            maxCpuSeconds = 0
            launchError = $_.Exception.Message
            capturedAt = (Get-Date).ToString('s')
        }
    }
    return [pscustomobject]@{
        label = $AttemptLabel
        succeeded = [bool]$result.succeeded
        exitCode = [int]$result.exitCode
        timedOut = [bool]$result.timedOut
        durationSeconds = $result.durationSeconds
        processId = $result.processId
        diagnostics = @($result.diagnostics)
        maxWorkingSetBytes = $result.maxWorkingSetBytes
        maxPrivateMemoryBytes = $result.maxPrivateMemoryBytes
        maxCpuSeconds = $result.maxCpuSeconds
        launchError = $result.launchError
        capturedAt = $result.capturedAt
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        engineStderrPath = $engineStderrPath
        launcherLogDir = $launcherLogDir
        startedAt = $startedAt.ToString('s')
        finishedAt = (Get-Date).ToString('s')
    }
}

function Update-AggregationAttemptHistory {
    param(
        [Parameter(Mandatory)] $Packet,
        [Parameter(Mandatory)][object[]] $Attempts
    )
    if ($null -eq $Packet.json -or -not (Test-Path -LiteralPath $Packet.json.FullName)) {
        throw 'Cannot update aggregate attempt history because the canonical JSON report is missing.'
    }
    $report = Read-JsonFileOrNull -Path $Packet.json.FullName
    if ($null -eq $report) {
        throw "Cannot update aggregate attempt history because the canonical JSON report could not be parsed: $($Packet.json.FullName)"
    }
    if ($null -eq $report.PSObject.Properties['aggregation']) {
        $report | Add-Member -NotePropertyName aggregation -NotePropertyValue ([pscustomobject]@{})
    }
    $report.aggregation.attempt_history = @($Attempts)
    ConvertTo-JsonFile -Value $report -Path $Packet.json.FullName
}

function Invoke-SimulationWithResilience {
    param(
        [Parameter(Mandatory)][string] $LauncherPath,
        [Parameter(Mandatory)] $TierConfig
    )
    $simulationConfig = Get-ObjectProperty -Object $config -Name 'simulationResilience' -Default @{}
    $retryCount = [int](Get-ObjectProperty -Object $simulationConfig -Name 'retryCount' -Default 1)
    $attempt = Invoke-SimulationAttempt -LauncherPath $LauncherPath -Arguments @($TierConfig.args) -AttemptLabel 'attempt_1' -TimeoutSeconds ([int]$TierConfig.timeoutSeconds)
    $script:simulationAttempts.Add($attempt)
    if ($attempt.succeeded) {
        return [pscustomobject]@{ mode = 'normal'; packet = $null }
    }

    Write-StepSummary -Step "$Tier simulation attempt 1" -Status 'failed; retrying' -Detail "exit=$($attempt.exitCode), timedOut=$($attempt.timedOut), stdout=$($attempt.stdoutPath), stderr=$($attempt.stderrPath)"
    if ($retryCount -gt 0) {
        $retry = Invoke-SimulationAttempt -LauncherPath $LauncherPath -Arguments @($TierConfig.args) -AttemptLabel 'attempt_2' -TimeoutSeconds ([int]$TierConfig.timeoutSeconds)
        $script:simulationAttempts.Add($retry)
        if ($retry.succeeded) {
            return [pscustomobject]@{ mode = 'recovered_after_retry'; packet = $null }
        }
        Write-StepSummary -Step "$Tier simulation attempt 2" -Status 'failed' -Detail "exit=$($retry.exitCode), timedOut=$($retry.timedOut), stdout=$($retry.stdoutPath), stderr=$($retry.stderrPath)"
    }

    $fallback = Get-ObjectProperty -Object $simulationConfig -Name 'lightFallback' -Default $null
    $fallbackEnabled = $Tier -eq 'Light' -and $null -ne $fallback -and [bool](Get-ObjectProperty -Object $fallback -Name 'enabled' -Default $false)
    if (-not $fallbackEnabled) {
        $script:simulationMode = 'unrecoverable_failure'
        throw "$Tier simulation failed after $($retryCount + 1) full-run attempt(s); no chunk fallback is configured. Attempt diagnostics are under logs/godot/ai_simulation/$runId."
    }

    $chunkCount = [int](Get-ObjectProperty -Object $fallback -Name 'chunkCount' -Default 2)
    $chunkRuns = [int](Get-ObjectProperty -Object $fallback -Name 'chunkRuns' -Default 120)
    if ($chunkCount -ne 2 -or $chunkRuns -ne 120) {
        $script:simulationMode = 'unrecoverable_failure'
        throw "Light fallback configuration must be exactly two chunks of 120 runs; got chunkCount=$chunkCount, chunkRuns=$chunkRuns."
    }
    $chunkArgsBase = @((Get-ObjectProperty -Object $fallback -Name 'args' -Default @()))
    $chunkJsonPaths = New-Object System.Collections.Generic.List[string]
    for ($chunkIndex = 0; $chunkIndex -lt $chunkCount; $chunkIndex++) {
        $chunkStartedAt = Get-Date
        $chunkArgs = New-Object System.Collections.Generic.List[string]
        foreach ($argument in $chunkArgsBase) {
            $chunkArgs.Add([string]$argument)
        }
        $chunkArgs.Add("--run-offset=$($chunkIndex * $chunkRuns)")
        $chunkArgs.Add("--report-label=light_chunk_$($chunkIndex + 1)_$runId")
        $chunkResult = Invoke-SimulationAttempt -LauncherPath $LauncherPath -Arguments @($chunkArgs.ToArray()) -AttemptLabel ("chunk_{0}" -f ($chunkIndex + 1)) -TimeoutSeconds ([int]$TierConfig.timeoutSeconds)
        $script:simulationAttempts.Add($chunkResult)
        if (-not $chunkResult.succeeded) {
            $script:simulationMode = 'unrecoverable_failure'
            throw "Light simulation chunk $($chunkIndex + 1) failed with exit=$($chunkResult.exitCode), timedOut=$($chunkResult.timedOut). Attempt diagnostics are under logs/godot/ai_simulation/$runId."
        }
        $chunkPacket = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config -EarliestWriteTime $chunkStartedAt
        if (-not $chunkPacket.complete) {
            throw "Light simulation chunk $($chunkIndex + 1) completed without a fresh report packet."
        }
        $chunkJsonPaths.Add($chunkPacket.json.FullName)
    }

    $aggregateMetadataPath = Join-Path (Join-Path (Join-Path $repoRoot 'logs\godot\ai_simulation') $runId) 'aggregation_metadata.json'
    ConvertTo-JsonFile -Value ([pscustomobject]@{
        mode = 'chunked_fallback'
        fallback_status = 'completed'
        chunk_count = $chunkCount
        chunk_runs = @($chunkRuns, $chunkRuns)
        source_reports = @($chunkJsonPaths.ToArray())
        attempt_history = @($script:simulationAttempts.ToArray())
    }) -Path $aggregateMetadataPath
    $aggregateStartedAt = Get-Date
    $aggregateArgs = @(
        '--test',
        "--profile=medium",
        "--runs=$($chunkCount * $chunkRuns)",
        '--max-waves=6',
        '--seed-count=5',
        '--strategy-group=standard_research',
        '--scenario-probes=auto',
        '--output-dir=res://.godot/ai_simulation',
        '--aggregate-metadata-file',
        $aggregateMetadataPath,
        "--report-label=light_chunked_fallback_$runId"
    )
    $aggregateResult = Invoke-SimulationAttempt -LauncherPath $LauncherPath -Arguments $aggregateArgs -AttemptLabel 'aggregate' -TimeoutSeconds ([int]$TierConfig.timeoutSeconds)
    $script:simulationAttempts.Add($aggregateResult)
    ConvertTo-JsonFile -Value ([pscustomobject]@{
        mode = 'chunked_fallback'
        fallback_status = if ($aggregateResult.succeeded) { 'completed' } else { 'failed' }
        chunk_count = $chunkCount
        chunk_runs = @($chunkRuns, $chunkRuns)
        source_reports = @($chunkJsonPaths.ToArray())
        attempt_history = @($script:simulationAttempts.ToArray())
    }) -Path $aggregateMetadataPath
    if (-not $aggregateResult.succeeded) {
        $script:simulationMode = 'unrecoverable_failure'
        throw "Light chunk aggregation failed with exit=$($aggregateResult.exitCode), timedOut=$($aggregateResult.timedOut)."
    }
    $aggregatePacket = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config -EarliestWriteTime $aggregateStartedAt
    if (-not $aggregatePacket.complete) {
        throw 'Light chunk aggregation completed without a fresh canonical report packet.'
    }
    Update-AggregationAttemptHistory -Packet $aggregatePacket -Attempts @($script:simulationAttempts.ToArray())
    return [pscustomobject]@{ mode = 'chunked_fallback'; packet = $aggregatePacket }
}

function Write-WorkflowState {
    param(
        [string] $Status,
        [string] $Failure,
        [object[]] $InitialGitStatus,
        [object[]] $FinalGitStatus,
        $Packet,
        $VisualEvidence,
        [object[]] $SimulationAttempts,
        [string] $SimulationMode
    )
    $findingsPath = Join-Path $stateDir 'findings.json'
    $statusPath = Join-Path $stateDir 'status.json'
    $dirtyInitial = @($InitialGitStatus).Count -gt 0
    $dirtyFinal = @($FinalGitStatus).Count -gt 0
    $baselineClassification = if ($dirtyInitial -or $dirtyFinal) { 'dirty-worktree evidence' } else { 'clean working-tree evidence' }
    $evidenceBaseline = [pscustomobject]@{
        classification = $baselineClassification
        dirtyInitial = $dirtyInitial
        dirtyFinal = $dirtyFinal
        initialStatusCount = @($InitialGitStatus).Count
        finalStatusCount = @($FinalGitStatus).Count
        applyTrust = if ($dirtyInitial -or $dirtyFinal) {
            'Do not treat this audit as committed-baseline project health. Apply-now remains gated by current git status and queued evidence.'
        } else {
            'Audit ran from a clean working tree at recorded status checks.'
        }
    }
    $state = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        runId = $runId
        tier = $Tier
        status = $Status
        failure = $Failure
        simulation = [pscustomobject]@{
            mode = $SimulationMode
            attempts = @($SimulationAttempts)
        }
        repoRoot = $repoRoot
        canonicalFiles = [pscustomobject]@{
            launcher = $config.launcher
            auditSpec = $config.auditSpec
            auditReport = $config.auditReport
        }
        initialGitStatus = @($InitialGitStatus)
        finalGitStatus = @($FinalGitStatus)
        evidenceBaseline = $evidenceBaseline
        checks = @($checks.ToArray())
        findings = @($findings.ToArray())
        gaps = @($gaps.ToArray())
        validationResults = @($validationResults.ToArray())
        artifacts = [pscustomobject]@{
            auditReport = $config.auditReport
            simulationPacket = [pscustomobject]@{
                complete = if ($null -ne $Packet) { [bool]$Packet.complete } else { $false }
                json = if ($null -ne $Packet -and $null -ne $Packet.json) { $Packet.json.FullName } else { $null }
                report = if ($null -ne $Packet -and $null -ne $Packet.report) { $Packet.report.FullName } else { $null }
                prompt = if ($null -ne $Packet -and $null -ne $Packet.prompt) { $Packet.prompt.FullName } else { $null }
            }
            visualReview = $VisualEvidence
            artifactFreshAfter = $startedAt.ToString('s')
        }
    }
    ConvertTo-JsonFile -Value $state -Path $findingsPath
    ConvertTo-JsonFile -Value ([pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        runId = $runId
        status = $Status
        tier = $Tier
        failure = $Failure
        simulation = [pscustomobject]@{
            mode = $SimulationMode
            attempts = @($SimulationAttempts)
        }
        evidenceBaseline = $evidenceBaseline
        report = (Join-Path $repoRoot $config.auditReport)
        findings = $findingsPath
    }) -Path $statusPath
}

Push-Location $repoRoot
try {
    $initialStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    $repoStatusLabel = if ($initialStatus.Count -gt 0) { 'dirty' } else { 'clean' }
    Add-Check -Name 'repo_status_initial' -Status $repoStatusLabel -Detail "$($initialStatus.Count) status rows"
    if ($initialStatus.Count -gt 0) {
        Add-Gap -Area 'Dirty worktree baseline' -Detail "Audit evidence was generated from a dirty working tree with $($initialStatus.Count) initial git status row(s)." -RecommendedEvidence 'Review or preserve current worktree changes before treating results as committed-baseline project health.'
    }

    $tierConfig = $config.tiers.$Tier
    if ($null -eq $tierConfig) {
        throw "No tier config found for $Tier."
    }

    if ($SkipSimulation) {
        Add-Check -Name 'simulation' -Status 'skipped' -Detail 'Skipped by parameter.'
        Write-StepSummary -Step "$Tier simulation" -Status 'skipped' -LogPath $config.playtestLog -Detail 'Skipped by parameter.'
        $packet = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config
    } else {
        $simulationStartedAt = Get-Date
        $launcherPath = if ($SimulationLauncherOverride.Trim().Length -gt 0) {
            (Resolve-Path -LiteralPath $SimulationLauncherOverride).Path
        } else {
            Join-Path $repoRoot $config.launcher
        }
        if (-not (Test-Path -LiteralPath $launcherPath)) {
            throw "Simulation launcher is missing: $launcherPath"
        }
        $simulationResult = Invoke-SimulationWithResilience -LauncherPath $launcherPath -TierConfig $tierConfig
        $simulationMode = [string]$simulationResult.mode
        $packet = $simulationResult.packet
        if ($null -eq $packet) {
            $packet = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config -EarliestWriteTime $simulationStartedAt
        }
        if (-not $packet.complete) {
            throw "Simulation completed but did not write a complete fresh packet under $($config.simulationDir)."
        }
        $simulationCheckStatus = if ($simulationMode -eq 'chunked_fallback') { 'passed with fallback' } elseif ($simulationMode -eq 'recovered_after_retry') { 'recovered after retry' } else { 'passed' }
        Add-Check -Name 'simulation' -Status $simulationCheckStatus -Detail "${Tier}: $($tierConfig.description); mode=$simulationMode"
        if ($simulationMode -eq 'chunked_fallback') {
            Add-Gap -Area 'AI simulation resilience' -Detail 'The full Light process required chunked fallback; the aggregate packet is valid but was not produced by one uninterrupted process.' -RecommendedEvidence 'Repeat a normal Light audit after the process environment is stable.'
        } elseif ($simulationMode -eq 'recovered_after_retry') {
            Add-Gap -Area 'AI simulation resilience' -Detail 'The first full Light process failed, but the one permitted retry completed successfully.' -RecommendedEvidence 'Review attempt diagnostics under logs/godot/ai_simulation before treating this as a stable baseline.'
        }
        Write-StepSummary -Step "$Tier simulation" -Status $simulationCheckStatus -LogPath $config.playtestLog -Detail "$($tierConfig.description); mode=$simulationMode; attempt artifacts under logs/godot/ai_simulation/$runId"
    }

    if ($SkipValidations) {
        Add-Check -Name 'focused_validation_matrix' -Status 'skipped' -Detail 'Skipped by parameter.'
        Write-StepSummary -Step 'focused validation matrix' -Status 'skipped' -Detail 'Skipped by parameter.'
    } else {
        foreach ($validation in $config.validations) {
            if ($SkipPlayableSurface -and [string]$validation.name -eq 'playable_surface_validation') {
                $validationResults.Add([pscustomobject]@{ name = $validation.name; status = 'skipped'; log = [string]$validation.log; expected = [string]$validation.expected })
                continue
            }
            if ([string]$validation.name -eq 'playable_surface_validation') {
                $visualStartedAt = Get-Date
            }
            Invoke-Validation -Validation $validation
        }
        Add-Check -Name 'focused_validation_matrix' -Status 'passed' -Detail "$($validationResults.Count)/$($config.validations.Count) validation rows recorded"
        Write-StepSummary -Step 'focused validation matrix' -Status 'passed' -Detail "$($validationResults.Count) validation rows recorded; logs are under logs/godot/"
    }

    Invoke-RepoCommand -Label 'git diff --check' -Command {
        git -c core.autocrlf=false diff --check
    }
    Add-Check -Name 'diff_hygiene' -Status 'passed' -Detail 'git diff --check exited 0'
    Write-StepSummary -Step 'git diff --check' -Status 'passed' -Detail 'git diff --check exited 0'

    Stop-NewGodotProcesses -PreExistingIds $preExistingGodotProcessIds
    Add-Check -Name 'post_audit_godot_process_cleanup' -Status 'passed' -Detail 'Stopped any Godot process started by this audit that remained after validations.'

    $reportText = Get-ReportText
    Add-ReportDerivedFindings -ReportText $reportText
    Add-SimulationDerivedFindings -Packet $packet
    $visualEvidence = Get-VisualReviewEvidence -RepoRoot $repoRoot -Config $config -EarliestWriteTime $visualStartedAt
    if ([int]$visualEvidence.count -eq 0) {
        Add-Gap -Area 'Visual review' -Detail 'No rendered screenshot evidence was produced or found for this workflow state.' -RecommendedEvidence 'Run playable-surface validation in a rendering-capable Godot session.'
    }
    Add-CurrentCoverageGaps -VisualEvidence $visualEvidence

    if ($gaps.Count -gt 0 -or $findings.Count -gt 0) {
        $finalStatus = 'pass with gaps'
    }
    $finalGitStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    Write-WorkflowState -Status $finalStatus -Failure $failureMessage -InitialGitStatus $initialStatus -FinalGitStatus $finalGitStatus -Packet $packet -VisualEvidence $visualEvidence -SimulationAttempts @($simulationAttempts.ToArray()) -SimulationMode $simulationMode
    Write-Host $finalStatus
    Write-StepSummary -Step 'workflow state write' -Status $finalStatus -LogPath (Join-Path $stateDir 'findings.json') -Detail "$($findings.Count) finding row(s), $($gaps.Count) gap row(s)"
} catch {
    $finalStatus = 'fail'
    $failureMessage = $_.Exception.Message
    if ($simulationAttempts.Count -gt 0 -and $simulationMode -eq 'not_run') {
        $simulationMode = 'unrecoverable_failure'
    }
    Add-Check -Name 'workflow_failure' -Status 'failed' -Detail $failureMessage
    if ($null -eq $packet) {
        $packet = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config -EarliestWriteTime $simulationStartedAt
    }
    $visualEvidence = Get-VisualReviewEvidence -RepoRoot $repoRoot -Config $config
    Stop-NewGodotProcesses -PreExistingIds $preExistingGodotProcessIds
    $finalGitStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    Write-WorkflowState -Status $finalStatus -Failure $failureMessage -InitialGitStatus $initialStatus -FinalGitStatus $finalGitStatus -Packet $packet -VisualEvidence $visualEvidence -SimulationAttempts @($simulationAttempts.ToArray()) -SimulationMode $simulationMode
    Write-StepSummary -Step 'workflow state write' -Status $finalStatus -LogPath (Join-Path $stateDir 'findings.json') -Detail $failureMessage
    $global:LASTEXITCODE = 1
    return
} finally {
    Pop-Location
}
$global:LASTEXITCODE = 0

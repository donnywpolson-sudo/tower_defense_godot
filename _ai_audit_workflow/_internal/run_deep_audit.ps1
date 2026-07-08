param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $SkipSimulation,
    [switch] $SkipValidations,
    [switch] $SkipPlayableSurface
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

function Write-WorkflowState {
    param(
        [string] $Status,
        [string] $Failure,
        [object[]] $InitialGitStatus,
        [object[]] $FinalGitStatus,
        $Packet,
        $VisualEvidence
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
        $launcherPath = Join-Path $repoRoot $config.launcher
        if (-not (Test-Path -LiteralPath $launcherPath)) {
            throw "Simulation launcher is missing: $launcherPath"
        }
        $simulationStdoutPath = Join-Path $stateDir 'simulation_stdout.log'
        Invoke-RepoProcess -Label "$Tier simulation" -FilePath $launcherPath -ArgumentList @($tierConfig.args) -WorkingDirectory $repoRoot -TimeoutSeconds ([int]$tierConfig.timeoutSeconds) -StdoutPath $simulationStdoutPath -MirrorRunProgress
        $packet = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config -EarliestWriteTime $simulationStartedAt
        if (-not $packet.complete) {
            throw "Simulation completed but did not write a complete fresh packet under $($config.simulationDir)."
        }
        Add-Check -Name 'simulation' -Status 'passed' -Detail "${Tier}: $($tierConfig.description)"
        Write-StepSummary -Step "$Tier simulation" -Status 'passed' -LogPath $config.playtestLog -Detail "$($tierConfig.description)"
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
    Write-WorkflowState -Status $finalStatus -Failure $failureMessage -InitialGitStatus $initialStatus -FinalGitStatus $finalGitStatus -Packet $packet -VisualEvidence $visualEvidence
    Write-Host $finalStatus
    Write-StepSummary -Step 'workflow state write' -Status $finalStatus -LogPath (Join-Path $stateDir 'findings.json') -Detail "$($findings.Count) finding row(s), $($gaps.Count) gap row(s)"
} catch {
    $finalStatus = 'fail'
    $failureMessage = $_.Exception.Message
    Add-Check -Name 'workflow_failure' -Status 'failed' -Detail $failureMessage
    $packet = Get-LatestSimulationPacket -RepoRoot $repoRoot -Config $config
    $visualEvidence = Get-VisualReviewEvidence -RepoRoot $repoRoot -Config $config
    Stop-NewGodotProcesses -PreExistingIds $preExistingGodotProcessIds
    $finalGitStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    Write-WorkflowState -Status $finalStatus -Failure $failureMessage -InitialGitStatus @() -FinalGitStatus $finalGitStatus -Packet $packet -VisualEvidence $visualEvidence
    Write-StepSummary -Step 'workflow state write' -Status $finalStatus -LogPath (Join-Path $stateDir 'findings.json') -Detail $failureMessage
    $global:LASTEXITCODE = 1
    return
} finally {
    Pop-Location
}
$global:LASTEXITCODE = 0

param(
    [string] $FindingId = '',
    [switch] $PrintPrompt,
    [switch] $MenuPreview,
    [switch] $RunCodex,
    [switch] $AllowDirtyApply
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'remediation_contract.ps1')

$repoRoot = Assert-TowerDefenseRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$promptPath = Join-Path $stateDir 'next_improvement_prompt.md'
$resultPath = Join-Path $stateDir 'last_improvement_result.json'
$queueValidation = Get-AuditQueueValidation -RepoRoot $repoRoot -Config $config
if (-not $queueValidation.valid) {
    Write-Host "Refusing improvement pass: $($queueValidation.reason)"
    Write-StepSummary -Step 'next fix preflight' -Status 'blocked' -LogPath $queueValidation.queuePath -Detail $queueValidation.reason
    exit 1
}

function Set-QueueItemHandled {
    param(
        [Parameter(Mandatory)] $Queue,
        [Parameter(Mandatory)][string] $ItemId,
        [Parameter(Mandatory)][string] $ResultPath,
        [Parameter(Mandatory)][string[]] $PostGitStatus
    )
    foreach ($queueItem in @($Queue.items)) {
        if ([string]$queueItem.id -eq $ItemId) {
            $queueItem.status = 'handled'
            $queueItem.resolutionStatus = 'handled'
            if ($null -eq $queueItem.PSObject.Properties['handledAt']) {
                $queueItem | Add-Member -NotePropertyName 'handledAt' -NotePropertyValue (Get-Date).ToString('s')
            } else {
                $queueItem.handledAt = (Get-Date).ToString('s')
            }
            if ($null -eq $queueItem.PSObject.Properties['resultPath']) {
                $queueItem | Add-Member -NotePropertyName 'resultPath' -NotePropertyValue $ResultPath
            } else {
                $queueItem.resultPath = $ResultPath
            }
            if ($null -eq $queueItem.PSObject.Properties['postGitStatus']) {
                $queueItem | Add-Member -NotePropertyName 'postGitStatus' -NotePropertyValue @($PostGitStatus)
            } else {
                $queueItem.postGitStatus = @($PostGitStatus)
            }
            if ($null -eq $queueItem.PSObject.Properties['postDiffCheck']) {
                $queueItem | Add-Member -NotePropertyName 'postDiffCheck' -NotePropertyValue 'passed'
            } else {
                $queueItem.postDiffCheck = 'passed'
            }
        }
    }
    ConvertTo-JsonFile -Value $Queue -Path $queuePath
}

function Get-RepoFileHashes {
    param([Parameter(Mandatory)][string] $RepoRoot)
    $hashes = @{}
    $paths = @(git -C $RepoRoot ls-files --cached --others --exclude-standard)
    if ((Get-SafeLastExitCode) -ne 0) { throw 'Unable to enumerate repository files.' }
    foreach ($relative in $paths) {
        $normalized = ([string]$relative).Replace('\','/')
        if ($normalized.StartsWith('_ai_audit_workflow/_internal/current/')) { continue }
        $fullPath = Join-Path $RepoRoot $relative
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) { $hashes[$normalized] = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash }
    }
    return $hashes
}

function Compare-RepoFileHashes {
    param([hashtable] $Before, [hashtable] $After)
    $allPaths = @($Before.Keys) + @($After.Keys) | Sort-Object -Unique
    return @($allPaths | Where-Object { -not $Before.ContainsKey($_) -or -not $After.ContainsKey($_) -or $Before[$_] -ne $After[$_] })
}

function Invoke-DiffCheckOrThrow {
    param([Parameter(Mandatory)][string] $RepoRoot)
    Push-Location $RepoRoot
    try {
        git -c core.autocrlf=false diff --check
        $exitCode = Get-SafeLastExitCode
        if ($exitCode -ne 0) {
            throw "git diff --check failed after Codex execution with exit code $exitCode."
        }
    } finally {
        Pop-Location
    }
}

function Invoke-IndependentValidator {
    param([Parameter(Mandatory)] $Item)
    $validator = Assert-RemediationValidatorSpec -Item $Item -RepoRoot $repoRoot
    $safeId = ([string]$Item.id -replace '[^A-Za-z0-9_-]', '_')
    $logDirectory = Join-Path $repoRoot 'logs\godot\remediation'
    if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $logPath = Join-Path $logDirectory ("{0}_{1}.log" -f $safeId, $stamp)
    $stdoutPath = [IO.Path]::ChangeExtension($logPath, '.stdout.log')
    $stderrPath = [IO.Path]::ChangeExtension($logPath, '.stderr.log')
    $startedAt = [DateTime]::UtcNow
    $arguments = @('--headless','--no-header','--log-file',$logPath,'--path',$repoRoot,'--script',[string]$validator.script,'--') + @($validator.args | ForEach-Object { [string]$_ })
    $processResult = Invoke-RepoProcess -Label ("validate-{0}" -f $safeId) -FilePath ([string]$config.godotExe) -ArgumentList $arguments -WorkingDirectory $repoRoot -TimeoutSeconds ([int]$validator.timeoutSeconds) -StdoutPath $stdoutPath -StderrPath $stderrPath -ReturnResult
    if (-not $processResult.succeeded) { throw "Independent validator failed with exit code $($processResult.exitCode)." }
    [void](Assert-FreshValidationToken -Paths @($logPath, $stdoutPath) -ExpectedToken ([string]$validator.expectedToken) -StartedAt $startedAt)
    return $logPath
}

function Set-QueueItemDeferred {
    param([Parameter(Mandatory)] $Queue, [Parameter(Mandatory)][string] $ItemId, [Parameter(Mandatory)][string] $Reason)
    foreach ($queueItem in @($Queue.items)) {
        if ([string]$queueItem.id -eq $ItemId) {
            $queueItem.status = 'deferred'
            $queueItem.resolutionStatus = 'deferred'
            if ($null -eq $queueItem.PSObject.Properties['deferredReason']) { $queueItem | Add-Member -NotePropertyName deferredReason -NotePropertyValue $Reason } else { $queueItem.deferredReason = $Reason }
        }
    }
    ConvertTo-JsonFile -Value $Queue -Path $queuePath
}

$queue = $queueValidation.queue
$items = @($queue.items)
if ($FindingId.Trim().Length -gt 0) {
    $item = $items | Where-Object { $_.id -eq $FindingId } | Select-Object -First 1
} else {
    $item = $items | Where-Object { $_.status -eq 'queued' } | Select-Object -First 1
}

if ($null -eq $item) {
    @'
# No Queued Improvement Item

The latest queue has no queued evidence-backed implementation finding or review-backed polish prompt.

Run a manual evidence pass for residual gaps, or run a fresh bounded audit after the current batch is complete.
'@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass with gaps'
    Write-Host "No queued item. Prompt written: $promptPath"
    Write-StepSummary -Step 'next fix prompt' -Status 'pass with gaps' -LogPath $promptPath -Detail 'No queued evidence-backed or review-backed item.'
    exit 0
}

$lane = if ($null -ne $item.PSObject.Properties['lane']) { [string]$item.lane } else { 'evidence-backed code fix' }
$isReviewBacked = $lane -eq 'review-backed polish fix'
$isGameplayExpansion = $lane -eq 'review-backed gameplay expansion'
$isReviewBacked = $isReviewBacked -or $isGameplayExpansion
$selectionLabel = if ($isGameplayExpansion) { 'review-backed gameplay expansion' } elseif ($isReviewBacked) { 'review-backed polish prompt' } else { 'evidence-backed fix' }
$sourceRunId = if ($null -ne $queue.PSObject.Properties['sourceRunId']) { [string]$queue.sourceRunId } else { '' }
$sourceStatus = if ($null -ne $queue.PSObject.Properties['sourceStatus']) { [string]$queue.sourceStatus } else { '' }
$sourceDirtyBaseline = if ($null -ne $queue.PSObject.Properties['sourceDirtyBaseline']) { [bool]$queue.sourceDirtyBaseline } else { $false }
$reviewRules = if ($isReviewBacked) {
@'
- This is review-backed, not already-proven code evidence.
- First inspect the cited screenshots/logs/telemetry.
- Implement a change only if that review confirms a concrete defect.
- If review finds no concrete defect, do not edit; report that no fix was applied.
'@
} else {
@'
- This is evidence-backed code work.
- Implement the smallest fix for the queued finding.
'@
}

$prompt = @"
# Tower Defense Improvement Pass

Use the latest audit evidence and handle only this queued item.

Finding id: $($item.id)
Lane: $lane
Area: $($item.area)
Score: $($item.score)
Title: $($item.title)
Source run id: $sourceRunId
Source status: $sourceStatus
Source dirty baseline: $sourceDirtyBaseline
Allowed files: $(@($item.allowedFiles) -join ', ')
Independent validator: $($item.validator.script) -> $($item.validator.expectedToken)

Evidence:
$($item.evidence)

Recommended smallest action:
$($item.recommendedAction)

Before editing:
- Send a short user-facing message explaining exactly what is being fixed.
- Include the finding id, lane, area, score, evidence, and intended smallest action.
- Then perform only that fix or review.

Rules:
- Confirm repo path and git status first.
- Preserve unrelated dirty files.
- Treat dirty-baseline audit evidence as current-worktree evidence only, not committed-baseline project health.
- Do not implement from weak or missing evidence.
- Treat simulation findings as investigation prompts until the exact current-code or current-data defect is verified.
- If verification does not confirm a concrete defect, do not edit; report the no-code-change outcome.
$reviewRules
- Keep the fix scoped to this finding.
- Use existing Godot nodes, autoloads, canonical data, and validation scripts.
- Keep Godot logs under logs/godot/.
- Do not run validation yourself; the wrapper independently runs the declared validator after checking the file delta.
- Your final response must be JSON only with exactly these fields: findingId, disposition, filesChanged, reason.
- disposition must be fixed, no_code_change, or deferred. filesChanged must be repo-relative and empty unless disposition is fixed.
- Do not update _ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md unless post-fix evidence materially changes and the edit is necessary.
"@

$prompt | Set-Content -LiteralPath $promptPath -Encoding UTF8
if ($MenuPreview) {
    Write-Host ''
    Write-Host 'Next fix/review preview'
    Write-Host ''
    Write-Host "Finding id: $($item.id)"
    Write-Host "Lane: $lane"
    Write-Host "Area: $($item.area)"
    Write-Host "Score: $($item.score)"
    Write-Host "Title: $($item.title)"
    Write-Host ''
    Write-Host "What will be reviewed/fixed: $($item.recommendedAction)"
    Write-Host ''
    Write-Host "Evidence: $($item.evidence)"
    Write-Host ''
    Write-Host "Prompt file: $promptPath"
} else {
    Write-Host 'pass'
    Write-Host ''
    Write-Host "Selected $selectionLabel"
    Write-Host ''
    Write-Host "Finding id: $($item.id)"
    Write-Host "Lane: $lane"
    Write-Host "Area: $($item.area)"
    Write-Host "Score: $($item.score)"
    Write-Host "Title: $($item.title)"
    Write-Host ''
    Write-Host "Next improvement prompt: $promptPath"
    Write-StepSummary -Step 'next fix prompt' -Status 'passed' -LogPath $promptPath -Detail "Prepared finding $($item.id): $($item.title)"
}
if ($PrintPrompt) {
    Get-Content -Raw -LiteralPath $promptPath
}

if ($RunCodex) {
    $preStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    if ($preStatus.Count -gt 0 -and -not $AllowDirtyApply) {
        Write-Host 'Refusing to launch Codex because the repo is dirty.'
        Write-Host 'Review or preserve the current worktree, then rerun with -AllowDirtyApply only if applying into this dirty tree is intentional.'
        Write-StepSummary -Step 'codex fix execution' -Status 'blocked' -LogPath $queuePath -Detail "$($preStatus.Count) existing git status row(s)."
        exit 1
    }
    [void](Assert-RemediationValidatorSpec -Item $item -RepoRoot $repoRoot)
    $allowedFiles = @($item.allowedFiles)
    if ($lane -eq 'evidence-backed code fix' -and $allowedFiles.Count -eq 0) { throw 'Implementation queue items require non-empty allowedFiles.' }
    $preHashes = Get-RepoFileHashes -RepoRoot $repoRoot

    $promptText = Get-Content -Raw -LiteralPath $promptPath
    Write-Host ''
    Write-Host "Launching Codex to perform this $selectionLabel now..."
    Write-Host "Result summary will be written to: $resultPath"
    $global:LASTEXITCODE = 0
    & codex exec --cd $repoRoot --output-last-message $resultPath $promptText
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        Write-Host "Codex fix execution failed with exit code $exitCode."
        Write-StepSummary -Step 'codex fix execution' -Status 'failed' -LogPath $resultPath -Detail "codex exec exit code $exitCode"
        exit $exitCode
    }
    $structuredResult = Read-StructuredRemediationResult -Path $resultPath -ExpectedFindingId ([string]$item.id)
    $postCodexHashes = Get-RepoFileHashes -RepoRoot $repoRoot
    $actualChangedFiles = @(Compare-RepoFileHashes -Before $preHashes -After $postCodexHashes)
    $actualSorted = @(Assert-RemediationDelta -Result $structuredResult -ActualChangedFiles $actualChangedFiles -AllowedFiles $allowedFiles)
    if ([string]$structuredResult.disposition -eq 'deferred') {
        Set-QueueItemDeferred -Queue $queue -ItemId $item.id -Reason ([string]$structuredResult.reason)
        Write-StepSummary -Step 'codex fix execution' -Status 'blocked' -LogPath $resultPath -Detail ([string]$structuredResult.reason)
        exit 0
    }
    $validatorLog = Invoke-IndependentValidator -Item $item
    Invoke-DiffCheckOrThrow -RepoRoot $repoRoot
    $postStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    Set-QueueItemHandled -Queue $queue -ItemId $item.id -ResultPath $resultPath -PostGitStatus $postStatus
    Write-StepSummary -Step 'codex fix execution' -Status 'passed' -LogPath $validatorLog -Detail "Structured result and declared delta verified; independent validator and git diff --check passed; $($postStatus.Count) git status row(s)."
}

param(
    [string] $FindingId = '',
    [switch] $PrintPrompt,
    [switch] $MenuPreview,
    [switch] $RunCodex,
    [switch] $AllowDirtyApply
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$promptPath = Join-Path $stateDir 'next_improvement_prompt.md'
$resultPath = Join-Path $stateDir 'last_improvement_result.md'

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

function Assert-ResultSummaryHasRequiredLines {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Codex did not write a result summary: $Path"
    }
    $text = Get-Content -Raw -LiteralPath $Path
    if ($text.Trim().Length -eq 0) {
        throw "Codex wrote an empty result summary: $Path"
    }
    if ($text -notmatch '(?im)^Files changed:\s*\S') {
        throw "Codex result summary must include an exact 'Files changed:' line before the queue item can be marked handled."
    }
    if ($text -notmatch '(?im)^Validation run:\s*\S') {
        throw "Codex result summary must include an exact 'Validation run:' line before the queue item can be marked handled."
    }
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

if (-not (Test-Path -LiteralPath $queuePath)) {
    Write-Host 'No improvement queue found yet.'
    Write-Host 'Choose Light audit or Deep audit first, then come back to Next fix/review prompt.'
    Write-StepSummary -Step 'next fix prompt' -Status 'skipped' -LogPath $queuePath -Detail 'No improvement queue found.'
    exit 0
}

$queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
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
$selectionLabel = if ($isReviewBacked) { 'review-backed polish prompt' } else { 'evidence-backed fix' }
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
$reviewRules
- Keep the fix scoped to this finding.
- Use existing Godot nodes, autoloads, canonical data, and validation scripts.
- Keep Godot logs under logs/godot/.
- Run targeted validation for the changed system.
- Run git diff --check before final.
- Final response must include exact lines starting with "Files changed:" and "Validation run:" so the wrapper can verify what changed and what was checked.
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
    Assert-ResultSummaryHasRequiredLines -Path $resultPath
    Invoke-DiffCheckOrThrow -RepoRoot $repoRoot
    $postStatus = @(Get-ShortGitStatus -RepoRoot $repoRoot)
    Set-QueueItemHandled -Queue $queue -ItemId $item.id -ResultPath $resultPath -PostGitStatus $postStatus
    Write-StepSummary -Step 'codex fix execution' -Status 'passed' -LogPath $resultPath -Detail "codex exec completed; git diff --check passed; $($postStatus.Count) git status row(s)."
}

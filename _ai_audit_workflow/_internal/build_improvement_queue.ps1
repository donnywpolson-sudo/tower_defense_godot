param(
    [switch] $AllowDirtyQueue
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo
$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$findingsPath = Join-Path $stateDir 'findings.json'
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$promptPath = Join-Path $stateDir 'next_improvement_prompt.md'

if (-not (Test-Path -LiteralPath $findingsPath)) {
    throw "Missing findings file. Run .\_ai_audit_workflow\RUN_AUDIT.ps1 first."
}

$state = Get-Content -Raw -LiteralPath $findingsPath | ConvertFrom-Json
$eligible = @($state.findings | Where-Object {
    $_.eligibleForFix -eq $true -and $_.evidenceBacked -eq $true -and $_.status -eq 'open'
} | Sort-Object score, area, id)

$items = New-Object System.Collections.Generic.List[object]

foreach ($finding in $eligible) {
    $items.Add([pscustomobject]@{
        id = $finding.id
        lane = 'evidence-backed code fix'
        area = $finding.area
        score = $finding.score
        title = $finding.title
        evidence = $finding.evidence
        recommendedAction = $finding.recommendedAction
        evidenceBacked = $true
        reviewBacked = $false
        status = 'queued'
    })
}

$reportPath = Join-Path $repoRoot $config.auditReport
$reportText = if (Test-Path -LiteralPath $reportPath) { Get-Content -Raw -LiteralPath $reportPath } else { '' }
if ($reportText -match '(?i)unsupported shop towers|unported systems|gameplay depth') {
    $items.Add([pscustomobject]@{
        id = 'review-gameplay-expansion'
        lane = 'review-backed gameplay expansion'
        area = 'Gameplay depth'
        score = 65
        title = 'Review the strongest verified gameplay-depth gap for one narrow expansion'
        evidence = "Audit report: $reportPath. The current report records unsupported or unported gameplay systems that need current-code verification before implementation."
        recommendedAction = 'Inspect the current canonical data and gameplay code for the smallest high-value expansion supported by the report, such as one tower family, progression interaction, enemy interaction, or meaningful choice. Implement only one narrow slice, preserve balance, and add or run targeted validation. If the report no longer matches current code, report no-code-change instead of editing.'
        evidenceBacked = $false
        reviewBacked = $true
        status = 'queued'
    })
}

$visualEvidence = Get-ObjectProperty -Object $state.artifacts -Name 'visualReview'
if ($visualEvidence -and [int](Get-ObjectProperty -Object $visualEvidence -Name 'count' -Default 0) -gt 0) {
    $items.Add([pscustomobject]@{
        id = 'review-visual-screenshots'
        lane = 'review-backed polish fix'
        area = 'Visual/UI polish'
        score = 75
        title = 'Review latest rendered screenshots for concrete visual/UI defects'
        evidence = "Screenshot folder: $($visualEvidence.folder); newest: $($visualEvidence.newest)"
        recommendedAction = 'Inspect the latest rendered screenshots, confirm only concrete visual defects, and fix the smallest confirmed issue. If no concrete defect is visible, report no visual fix instead of editing.'
        evidenceBacked = $false
        reviewBacked = $true
        status = 'queued'
    })
}

$sourceBaseline = Get-ObjectProperty -Object $state -Name 'evidenceBaseline'
$sourceDirtyBaseline = $false
if ($null -ne $sourceBaseline) {
    $sourceDirtyBaseline = [bool](Get-ObjectProperty -Object $sourceBaseline -Name 'dirtyInitial' -Default $false) -or [bool](Get-ObjectProperty -Object $sourceBaseline -Name 'dirtyFinal' -Default $false)
}
$dirtyQueueBlocked = $sourceDirtyBaseline -and -not $AllowDirtyQueue
if ($dirtyQueueBlocked) {
    $queuedItems = @()
} else {
    $queuedItems = @($items.ToArray())
}
$queuedItemCount = @($queuedItems).Count
$blockedDirtyQueueCount = if ($dirtyQueueBlocked) { $items.Count } else { 0 }
$queuePolicy = if ($dirtyQueueBlocked) {
    'Dirty-baseline audit output is current-worktree evidence only. Apply-ready queue generation is blocked by default; rerun from a clean worktree or pass -AllowDirtyQueue intentionally.'
} elseif ($sourceDirtyBaseline) {
    'Dirty-baseline queue generation was explicitly allowed. Treat every queued item as current-worktree evidence only, not committed-baseline project health. Applying still requires the separate dirty apply gate.'
} else {
    'Evidence-backed code findings are first priority. Review-backed gameplay expansion and polish prompts must inspect current evidence and confirm a concrete, scoped improvement before editing.'
}

$queue = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('s')
    sourceFindings = $findingsPath
    sourceRunId = Get-ObjectProperty -Object $state -Name 'runId' -Default ''
    sourceStatus = Get-ObjectProperty -Object $state -Name 'status' -Default ''
    sourceDirtyBaseline = $sourceDirtyBaseline
    dirtyQueueBlocked = $dirtyQueueBlocked
    blockedDirtyQueueCount = $blockedDirtyQueueCount
    allowDirtyQueue = [bool]$AllowDirtyQueue
    count = $queuedItemCount
    evidenceBackedCount = @($queuedItems | Where-Object { $_.evidenceBacked -eq $true }).Count
    reviewBackedCount = @($queuedItems | Where-Object { $_.reviewBacked -eq $true }).Count
    policy = $queuePolicy
    items = @($queuedItems)
}

ConvertTo-JsonFile -Value $queue -Path $queuePath

if ($dirtyQueueBlocked) {
    @"
# No Queued Improvement Item

The latest audit found $blockedDirtyQueueCount potential item(s), but apply-ready
queue generation is blocked because the source audit evidence came from a dirty
working tree.

Source findings: $findingsPath
Source run id: $($queue.sourceRunId)
Source status: $($queue.sourceStatus)
Source dirty baseline: $($queue.sourceDirtyBaseline)

Review the evidence as current-worktree diagnostics only. To generate a queue,
rerun from a clean worktree, or rerun with -AllowDirtyQueue if queuing from this
dirty baseline is intentional. Do not apply an older prompt from this file.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass with gaps'
    Write-Host "Dirty-baseline audit blocked $blockedDirtyQueueCount apply-ready queue item(s). Rerun clean or pass -AllowDirtyQueue intentionally."
    Write-Host "Next prompt invalidated: $promptPath"
} elseif ($queue.count -eq 0) {
    @"
# No Queued Improvement Item

The latest audit queue has no queued evidence-backed code fix or review-backed
polish prompt.

Source findings: $findingsPath
Source run id: $($queue.sourceRunId)
Source status: $($queue.sourceStatus)
Source dirty baseline: $($queue.sourceDirtyBaseline)

Review the gaps in findings.json, or run a fresh bounded audit after the current
batch is complete. Do not apply an older prompt from this file.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass with gaps'
    Write-Host "No evidence-backed or review-backed improvement items are queued. Review gaps in $findingsPath."
    Write-Host "Next prompt invalidated: $promptPath"
} else {
    $firstItem = $queuedItems[0]
    @"
# Queued Improvement Item Available

The latest audit queue contains queued work. Use RUN_AUDIT.ps1 -NextFix to
generate the exact prompt for the current first queued item.

First queued item: $($firstItem.id)
Lane: $($firstItem.lane)
Area: $($firstItem.area)
Score: $($firstItem.score)
Title: $($firstItem.title)

Source findings: $findingsPath
Source run id: $($queue.sourceRunId)
Source status: $($queue.sourceStatus)
Source dirty baseline: $($queue.sourceDirtyBaseline)
Allow dirty queue: $($queue.allowDirtyQueue)
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass'
    Write-Host "Queued $($queue.count) improvement item(s): $($queue.evidenceBackedCount) evidence-backed, $($queue.reviewBackedCount) review-backed. $queuePath"
    Write-Host "Next prompt summary written: $promptPath"
}

param()

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

$visualEvidence = Get-ObjectProperty -Object $state.artifacts -Name 'visualReview'
if ($visualEvidence -and [int](Get-ObjectProperty -Object $visualEvidence -Name 'count' -Default 0) -gt 0) {
    $visualGap = @($state.gaps | Where-Object { $_.area -eq 'Visual review' }) | Select-Object -First 1
    if ($null -ne $visualGap) {
        $items.Add([pscustomobject]@{
            id = 'review-visual-screenshots'
            lane = 'review-backed polish fix'
            area = 'Visual/UI polish'
            score = 75
            title = 'Review latest rendered screenshots for concrete visual/UI defects'
            evidence = "Screenshot folder: $($visualEvidence.folder); newest: $($visualEvidence.newest)"
            recommendedAction = 'Inspect the latest rendered screenshots, confirm only concrete visual defects, and fix the smallest confirmed issue.'
            evidenceBacked = $false
            reviewBacked = $true
            status = 'queued'
        })
    }
}

$codeFixCount = @($items | Where-Object { $_.lane -eq 'evidence-backed code fix' }).Count
$reviewFixCount = @($items | Where-Object { $_.lane -eq 'review-backed polish fix' }).Count
$sourceBaseline = Get-ObjectProperty -Object $state -Name 'evidenceBaseline'
$sourceDirtyBaseline = $false
if ($null -ne $sourceBaseline) {
    $sourceDirtyBaseline = [bool](Get-ObjectProperty -Object $sourceBaseline -Name 'dirtyInitial' -Default $false) -or [bool](Get-ObjectProperty -Object $sourceBaseline -Name 'dirtyFinal' -Default $false)
}

$queue = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('s')
    sourceFindings = $findingsPath
    sourceRunId = Get-ObjectProperty -Object $state -Name 'runId' -Default ''
    sourceStatus = Get-ObjectProperty -Object $state -Name 'status' -Default ''
    sourceDirtyBaseline = $sourceDirtyBaseline
    count = $items.Count
    evidenceBackedCount = $codeFixCount
    reviewBackedCount = $reviewFixCount
    policy = 'Evidence-backed code findings are first priority. Review-backed polish prompts may inspect screenshots or telemetry but must confirm concrete defects before editing. Dirty-baseline audit output is not committed-baseline project health.'
    items = @($items.ToArray())
}

ConvertTo-JsonFile -Value $queue -Path $queuePath

if ($items.Count -eq 0) {
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
    $firstItem = $items[0]
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
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass'
    Write-Host "Queued $($items.Count) improvement item(s): $codeFixCount evidence-backed, $reviewFixCount review-backed. $queuePath"
    Write-Host "Next prompt summary written: $promptPath"
}

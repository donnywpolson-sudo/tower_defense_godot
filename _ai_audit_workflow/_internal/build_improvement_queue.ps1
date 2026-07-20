param(
    [switch] $AllowDirtyQueue,
    [switch] $IncludeDiagnosticCandidates
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
$sourcePacket = Get-ObjectProperty -Object $state.artifacts -Name 'simulationPacket'
$sourcePacketId = [string](Get-ObjectProperty -Object $sourcePacket -Name 'packetId' -Default '')
$sourcePacketJson = [string](Get-ObjectProperty -Object $sourcePacket -Name 'json' -Default '')
$packetReport = if ($sourcePacketJson.Trim().Length -gt 0) { Read-JsonFileOrNull -Path $sourcePacketJson } else { $null }
$packetComplete = $null -ne $sourcePacket -and [bool](Get-ObjectProperty -Object $sourcePacket -Name 'complete' -Default $false) -and $null -ne $packetReport -and $sourcePacketId.Trim().Length -gt 0
$packetGate = if ($packetComplete) { '' } else { 'Current findings do not reference a complete self-identifying packet; queue generation is report-only and cannot create apply-ready work.' }
$eligible = @($state.findings | Where-Object {
    $_.eligibleForFix -eq $true -and $_.evidenceBacked -eq $true -and $_.status -eq 'open'
} | Sort-Object score, area, id)

$items = New-Object System.Collections.Generic.List[object]
$itemIds = @{}

function Add-QueueItem {
    param([Parameter(Mandatory)] $Item)
    $id = [string]$Item.id
    if ($id.Trim().Length -eq 0 -or $itemIds.ContainsKey($id)) {
        return
    }
    $itemIds[$id] = $true
    $items.Add($Item)
}

function New-ValidatorSpec {
    param([string] $Area, [string] $Lane)
    $normalized = ($Area + ' ' + $Lane).ToLowerInvariant()
    $script = 'res://scripts/tools/run_vertical_slice_smoke.gd'
    $token = 'VERTICAL_SLICE_SMOKE_OK'
    if ($normalized -match 'visual|ui|surface') { $script = 'res://scripts/tools/run_playable_surface_validation.gd'; $token = 'PLAYABLE_SURFACE_VALIDATION_OK' }
    elseif ($normalized -match 'persist|save|load') { $script = 'res://scripts/tools/run_persistence_validation.gd'; $token = 'PERSISTENCE_VALIDATION_OK' }
    elseif ($normalized -match 'projectile') { $script = 'res://scripts/tools/run_projectile_validation.gd'; $token = 'PROJECTILE_VALIDATION_OK' }
    elseif ($normalized -match 'target') { $script = 'res://scripts/tools/run_targeting_validation.gd'; $token = 'TARGETING_VALIDATION_OK' }
    elseif ($normalized -match 'upgrade|tower|branch') { $script = 'res://scripts/tools/run_upgrade_panel_validation.gd'; $token = 'UPGRADE_PANEL_VALIDATION_OK' }
    elseif ($normalized -match 'data|balance|progress') { $script = 'res://scripts/tools/run_data_validation.gd'; $token = 'DATA_VALIDATION_OK' }
    return [pscustomobject]@{ script = $script; args = @(); expectedToken = $token; timeoutSeconds = 600 }
}

function Get-DefaultAllowedFiles {
    param([string] $Area)
    $normalized = $Area.ToLowerInvariant()
    if ($normalized -match 'visual|ui|surface') { return @('scenes/*', 'scripts/game/*', 'scripts/ui/*', 'scripts/tools/*') }
    if ($normalized -match 'data|balance|progress') { return @('data/game_data.json', 'scripts/autoload/*', 'scripts/game/*', 'scripts/tools/*') }
    if ($normalized -match 'workflow|audit') { return @('_ai_audit_workflow/*', 'scripts/tools/*') }
    return @('scripts/game/*', 'scripts/autoload/*', 'scripts/tools/*')
}

foreach ($finding in $eligible) {
    Add-QueueItem ([pscustomobject]@{
        id = $finding.id
        lane = 'evidence-backed code fix'
        area = $finding.area
        score = $finding.score
        title = $finding.title
        evidence = $finding.evidence
        recommendedAction = $finding.recommendedAction
        sourcePacketId = $sourcePacketId
        confidence = if ($null -ne $finding.PSObject.Properties['confidence']) { $finding.confidence } else { 'medium' }
        reproduction = if ($null -ne $finding.PSObject.Properties['reproduction']) { $finding.reproduction } else { $null }
        validationCommand = if ($null -ne $finding.PSObject.Properties['recommendedValidation']) { $finding.recommendedValidation } else { 'Run the narrow validator for the affected subsystem.' }
        allowedFiles = if ($null -ne $finding.PSObject.Properties['allowedFiles'] -and @($finding.allowedFiles).Count -gt 0) { @($finding.allowedFiles) } else { @(Get-DefaultAllowedFiles -Area ([string]$finding.area)) }
        validator = New-ValidatorSpec -Area ([string]$finding.area) -Lane 'evidence-backed code fix'
        noCodeChangeIf = if ($null -ne $finding.PSObject.Properties['noCodeChangeIf']) { $finding.noCodeChangeIf } else { 'Do not edit until the finding is reproduced against current code.' }
        resolutionStatus = 'queued'
        evidenceBacked = $true
        reviewBacked = $false
        status = 'queued'
    })
}

if ($IncludeDiagnosticCandidates) {
    foreach ($finding in @($state.findings | Where-Object { $_.status -eq 'open' } | Sort-Object score, area, id)) {
        $evidenceBacked = [bool](Get-ObjectProperty -Object $finding -Name 'evidenceBacked' -Default $false)
        $eligibleForFix = [bool](Get-ObjectProperty -Object $finding -Name 'eligibleForFix' -Default $false)
        $lane = if ($eligibleForFix -and $evidenceBacked) { 'evidence-backed code fix' } else { 'diagnostic candidate review' }
        Add-QueueItem ([pscustomobject]@{
            id = [string]$finding.id
            lane = $lane
            area = [string]$finding.area
            score = [int](Get-ObjectProperty -Object $finding -Name 'score' -Default 0)
            title = [string]$finding.title
            evidence = [string]$finding.evidence
            recommendedAction = [string]$finding.recommendedAction
            sourcePacketId = $sourcePacketId
            confidence = Get-ObjectProperty -Object $finding -Name 'confidence' -Default 'low'
            reproduction = Get-ObjectProperty -Object $finding -Name 'reproduction' -Default $null
            validationCommand = Get-ObjectProperty -Object $finding -Name 'recommendedValidation' -Default 'Run the narrow validator for the affected subsystem and reproduce the cited evidence.'
            allowedFiles = @((Get-ObjectProperty -Object $finding -Name 'allowedFiles' -Default @()))
            validator = New-ValidatorSpec -Area ([string]$finding.area) -Lane $lane
            noCodeChangeIf = Get-ObjectProperty -Object $finding -Name 'noCodeChangeIf' -Default 'Do not edit unless the current code reproduces the finding and the targeted validation fails for the same reason.'
            resolutionStatus = 'queued'
            evidenceBacked = $evidenceBacked
            reviewBacked = (-not $evidenceBacked)
            status = 'queued'
        })
    }
    foreach ($gap in @($state.gaps)) {
        $area = [string](Get-ObjectProperty -Object $gap -Name 'area' -Default 'Audit coverage')
        $detail = [string](Get-ObjectProperty -Object $gap -Name 'detail' -Default 'The audit recorded an unresolved coverage or workflow gap.')
        $gapId = 'gap-' + (($area + '-' + $detail) -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
        Add-QueueItem ([pscustomobject]@{
            id = $gapId
            lane = 'audit-gap review'
            area = $area
            score = 10
            title = "Resolve or explicitly defer audit gap: $area"
            evidence = $detail
            recommendedAction = [string](Get-ObjectProperty -Object $gap -Name 'recommendedEvidence' -Default 'Inspect the gap against the current repo and add the narrowest proof or fix needed.')
            sourcePacketId = $sourcePacketId
            confidence = 'low'
            reproduction = $null
            validationCommand = 'Run the narrow validation or inspection that directly addresses this gap.'
            allowedFiles = @()
            validator = New-ValidatorSpec -Area $area -Lane 'audit-gap review'
            noCodeChangeIf = 'Do not change gameplay or data merely to eliminate a coverage gap; record the missing proof and defer it when no concrete defect is reproduced.'
            resolutionStatus = 'queued'
            evidenceBacked = $false
            reviewBacked = $true
            status = 'queued'
        })
    }
}

if ($packetComplete -and $null -ne $packetReport -and ($null -ne $packetReport.PSObject.Properties['gameplay_depth_metrics'])) {
    Add-QueueItem ([pscustomobject]@{
        id = 'review-gameplay-expansion'
        lane = 'review-backed gameplay expansion'
        area = 'Gameplay depth'
        score = 65
        title = 'Review the strongest verified gameplay-depth gap for one narrow expansion'
        evidence = "Current packet $sourcePacketId JSON: $sourcePacketJson. Gameplay-depth telemetry is a candidate signal and requires current-code review."
        recommendedAction = 'Inspect the current canonical data and gameplay code for the smallest high-value expansion supported by the report, such as one tower family, progression interaction, enemy interaction, or meaningful choice. Implement only one narrow slice, preserve balance, and add or run targeted validation. If the report no longer matches current code, report no-code-change instead of editing.'
        sourcePacketId = $sourcePacketId
        confidence = 'low'
        reproduction = [pscustomobject]@{ packetId = $sourcePacketId; json = $sourcePacketJson; note = 'Candidate telemetry only; no code change without counterfactual or replay evidence.' }
        validationCommand = 'Run a bounded deterministic counterfactual and the narrow gameplay validator before implementation.'
        allowedFiles = @('scripts/game/vertical_slice_game.gd', 'data/game_data.json', 'scripts/tools/*')
        validator = [pscustomobject]@{ script = 'res://scripts/tools/run_tower_branch_matrix_validation.gd'; args = @(); expectedToken = 'TOWER_BRANCH_MATRIX_VALIDATION_OK'; timeoutSeconds = 3600 }
        noCodeChangeIf = 'Do not implement if the candidate is explained by bot policy, incomplete runtime support, or weak telemetry.'
        resolutionStatus = 'queued'
        evidenceBacked = $false
        reviewBacked = $true
        status = 'queued'
    })
}

$visualEvidence = Get-ObjectProperty -Object $state.artifacts -Name 'visualReview'
if ($visualEvidence -and [int](Get-ObjectProperty -Object $visualEvidence -Name 'count' -Default 0) -gt 0) {
    Add-QueueItem ([pscustomobject]@{
        id = 'review-visual-screenshots'
        lane = 'review-backed polish fix'
        area = 'Visual/UI polish'
        score = 75
        title = 'Review latest rendered screenshots for concrete visual/UI defects'
        evidence = "Screenshot folder: $($visualEvidence.folder); newest: $($visualEvidence.newest)"
        recommendedAction = 'Inspect the latest rendered screenshots, confirm only concrete visual defects, and fix the smallest confirmed issue. If no concrete defect is visible, report no visual fix instead of editing.'
        sourcePacketId = $sourcePacketId
        confidence = 'low'
        reproduction = [pscustomobject]@{ packetId = $sourcePacketId; screenshots = @($visualEvidence.files) }
        validationCommand = 'Run playable-surface validation and screenshot geometry assertions.'
        allowedFiles = @('scenes/*', 'scripts/game/*', 'scripts/ui/*')
        validator = [pscustomobject]@{ script = 'res://scripts/tools/run_playable_surface_validation.gd'; args = @(); expectedToken = 'PLAYABLE_SURFACE_VALIDATION_OK'; timeoutSeconds = 600 }
        noCodeChangeIf = 'Do not edit if visual inspection finds no concrete overlap, clipping, unreadable text, or blank-panel defect.'
        resolutionStatus = 'queued'
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
if (-not $packetComplete) {
    $queuedItems = @()
} elseif ($dirtyQueueBlocked) {
    $queuedItems = @()
} else {
    $queuedItems = @($items.ToArray())
}
$queuedItemCount = @($queuedItems).Count
$blockedDirtyQueueCount = if ($dirtyQueueBlocked) { $items.Count } else { 0 }
$queuePolicy = if (-not $packetComplete) {
    $packetGate
} elseif ($dirtyQueueBlocked) {
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
    sourcePacketId = $sourcePacketId
    packetComplete = $packetComplete
    packetGate = $packetGate
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

if (-not $packetComplete) {
    @"
# No Queued Improvement Item

$packetGate

Source findings: $findingsPath
Source run id: $($queue.sourceRunId)
Source packet id: $sourcePacketId
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-Host 'pass with gaps'
    Write-Host $packetGate
} elseif ($dirtyQueueBlocked) {
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
	$promptLines = New-Object System.Collections.Generic.List[string]
    $promptLines.Add('# Pursue Goal: Remediate the Complete AI Audit Candidate Set')
	$promptLines.Add('')
    $promptLines.Add('Pursue this remediation goal autonomously in the current Godot repository until every queued finding and audit gap has a resolved, deferred, or no-code-change disposition. Do not stop after the first fix and do not ask the user to babysit item-by-item decisions.')
	$promptLines.Add('')
	$promptLines.Add('## Evidence and scope')
	$promptLines.Add("- Source findings: $findingsPath")
	$promptLines.Add("- Source run id: $($queue.sourceRunId)")
	$promptLines.Add("- Source packet id: $sourcePacketId")
	$promptLines.Add("- Source status: $($queue.sourceStatus)")
	$promptLines.Add("- Source dirty baseline: $($queue.sourceDirtyBaseline)")
	$promptLines.Add('')
	$promptLines.Add('## Autonomous remediation loop')
	$promptLines.Add('1. Confirm the repo path and inspect `git status --short`; preserve unrelated dirty files.')
	$promptLines.Add('2. Read the full findings and cited packet evidence before editing.')
    $promptLines.Add('3. Process every queued item in priority order. Verify the current-code or current-data defect, make the smallest safe fix, and add or run focused validation.')
    $promptLines.Add('4. If evidence does not reproduce the issue, do not edit; record the reason and continue to the next item. A candidate may be deferred, but it may not be silently ignored.')
    $promptLines.Add('5. After each related batch, run the narrow validators and repair regressions before moving on. Finish with `git diff --check` and report every item disposition, including deferred items.')
	$promptLines.Add('')
	$promptLines.Add('## Rules')
    $promptLines.Add('- Treat simulation telemetry, screenshots, and coverage gaps as candidate evidence to verify, not automatic proof.')
	$promptLines.Add('- Keep canonical gameplay/data in the main project; do not move rules into the bot.')
	$promptLines.Add('- Keep changes small, playable, and reviewable. Do not stage, commit, push, delete, or revert unrelated files.')
    $promptLines.Add('- Preserve known gaps and weak coverage as deferred unless new evidence confirms a concrete defect; do not invent fixes just to make the queue empty.')
	$promptLines.Add('- Keep Godot logs under `logs/godot/`.')
	$promptLines.Add('')
	$promptLines.Add('## Queued findings')
	foreach ($item in @($queuedItems)) {
	    $promptLines.Add(('### {0}: {1}' -f $item.id, $item.title))
	    $promptLines.Add("- Lane: $($item.lane)")
	    $promptLines.Add("- Area: $($item.area)")
	    $promptLines.Add("- Score: $($item.score)")
	    $promptLines.Add("- Evidence: $($item.evidence)")
	    $promptLines.Add("- Recommended action: $($item.recommendedAction)")
	    $promptLines.Add("- Validation: $($item.validationCommand)")
	    $promptLines.Add("- No-code-change condition: $($item.noCodeChangeIf)")
	    $promptLines.Add('')
	}
	$promptLines.Add('## Completion criteria')
    $promptLines.Add('- Every queued item has a resolved, deferred, or no-code-change disposition with a short reason.')
	$promptLines.Add('- Every implemented fix has focused validation evidence.')
	$promptLines.Add('- Final response includes exact lines starting with `Files changed:` and `Validation run:` plus deferred finding IDs and reasons.')
	($promptLines -join "`r`n") | Set-Content -LiteralPath $promptPath -Encoding UTF8
	Write-Host @"
# Pursue Goal Prompt Ready

The latest audit queue contains $($queue.count) queued item(s). Copy the full
contents of this file into Codex to pursue remediation autonomously across all
queued findings. The prompt is evidence-first: weak or non-reproducible items
must be deferred rather than force-fixed.

Source findings: $findingsPath
Source run id: $($queue.sourceRunId)
Source status: $($queue.sourceStatus)
Source dirty baseline: $($queue.sourceDirtyBaseline)
Allow dirty queue: $($queue.allowDirtyQueue)
"@
    Write-Host 'pass'
    Write-Host "Queued $($queue.count) improvement item(s): $($queue.evidenceBackedCount) evidence-backed, $($queue.reviewBackedCount) review-backed. $queuePath"
    Write-Host "Pursue goal prompt written: $promptPath"
}

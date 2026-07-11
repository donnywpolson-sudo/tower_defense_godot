param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $SkipAudit,
    [switch] $AllowDirtyQueue,
    [string] $SimulationLauncherOverride = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo

function Invalidate-ImprovementQueue {
    param([Parameter(Mandatory)][string] $Reason)
    $config = Read-WorkflowConfig
    $stateDir = Ensure-WorkflowState -Config $config
    $findingsPath = Join-Path $stateDir 'findings.json'
    $findings = Read-JsonFileOrNull -Path $findingsPath
    $queuePath = Join-Path $stateDir 'improvement_queue.json'
    $queue = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        sourceFindings = $findingsPath
        sourceRunId = Get-ObjectProperty -Object $findings -Name 'runId' -Default ''
        sourceStatus = Get-ObjectProperty -Object $findings -Name 'status' -Default 'fail'
        invalidated = $true
        invalidationReason = $Reason
        count = 0
        evidenceBackedCount = 0
        reviewBackedCount = 0
        items = @()
    }
    ConvertTo-JsonFile -Value $queue -Path $queuePath
    $promptPath = Join-Path $stateDir 'next_improvement_prompt.md'
    @"
# No Queued Improvement Item

The latest audit failed before producing applyable evidence.

Source status: $($queue.sourceStatus)
Reason: $Reason

Run a fresh successful audit before applying any improvement.
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
    Write-StepSummary -Step 'improvement queue invalidation' -Status 'blocked' -LogPath $queuePath -Detail $Reason
}

if ($SkipAudit) {
    & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier $Tier -SkipSimulation -SkipValidations -SkipPlayableSurface -SimulationLauncherOverride $SimulationLauncherOverride
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        Invalidate-ImprovementQueue -Reason "Audit failed with exit code $exitCode."
        Write-Host 'fail'
        $global:LASTEXITCODE = $exitCode
        throw "Audit failed with exit code $exitCode; improvement queue generation was blocked."
    }
} else {
    & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier $Tier -SimulationLauncherOverride $SimulationLauncherOverride
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        Invalidate-ImprovementQueue -Reason "Audit failed with exit code $exitCode."
        Write-Host 'fail'
        $global:LASTEXITCODE = $exitCode
        throw "Audit failed with exit code $exitCode; improvement queue generation was blocked."
    }
}

& (Join-Path $PSScriptRoot 'build_improvement_queue.ps1') -AllowDirtyQueue:$AllowDirtyQueue
$exitCode = Get-SafeLastExitCode
if ($exitCode -ne 0) {
    Write-Host 'fail'
    $global:LASTEXITCODE = $exitCode
    throw "Improvement queue build failed with exit code $exitCode."
}

$config = Read-WorkflowConfig
$stateDir = Ensure-WorkflowState -Config $config
$queuePath = Join-Path $stateDir 'improvement_queue.json'
$queue = Read-JsonFileOrNull -Path $queuePath
$queueCount = [int](Get-ObjectProperty -Object $queue -Name 'count' -Default 0)
$evidenceBackedCount = [int](Get-ObjectProperty -Object $queue -Name 'evidenceBackedCount' -Default 0)
$reviewBackedCount = [int](Get-ObjectProperty -Object $queue -Name 'reviewBackedCount' -Default 0)
Write-StepSummary -Step 'improvement queue build' -Status 'passed' -LogPath $queuePath -Detail "$queueCount queued item(s): $evidenceBackedCount evidence-backed, $reviewBackedCount review-backed"
Write-Host 'pass'
Write-Host 'Audit state and queue generation complete.'
$global:LASTEXITCODE = 0

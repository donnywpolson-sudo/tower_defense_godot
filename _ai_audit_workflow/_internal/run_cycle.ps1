param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $SkipAudit,
    [switch] $AllowDirtyQueue
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo

if ($SkipAudit) {
    & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier $Tier -SkipSimulation -SkipValidations -SkipPlayableSurface
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        Write-Host 'fail'
        $global:LASTEXITCODE = $exitCode
        return
    }
} else {
    & (Join-Path $PSScriptRoot 'run_deep_audit.ps1') -Tier $Tier
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        Write-Host 'fail'
        $global:LASTEXITCODE = $exitCode
        return
    }
}

& (Join-Path $PSScriptRoot 'build_improvement_queue.ps1') -AllowDirtyQueue:$AllowDirtyQueue
$exitCode = Get-SafeLastExitCode
if ($exitCode -ne 0) {
    Write-Host 'fail'
    $global:LASTEXITCODE = $exitCode
    return
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

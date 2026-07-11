param(
    [ValidateSet('Light', 'Deep')]
    [string] $Tier = 'Light',
    [switch] $NextFix,
    [switch] $AutoImprove,
    [ValidateRange(1, 5)]
    [int] $MaxFixes = 1,
    [switch] $SkipAudit,
    [switch] $AllowDirtyQueue,
    [switch] $AllowDirtyApply,
    [switch] $PauseOnExit
)

$ErrorActionPreference = 'Stop'
$internal = Join-Path $PSScriptRoot '_internal'
$preflightIssues = New-Object System.Collections.Generic.List[object]
$transcriptStarted = $false
$transcriptPath = $null
$transcriptArchivePath = $null

function Pause-IfInteractive {
    param([bool] $Interactive)
    if ($Interactive) {
        Write-Host ''
        Read-Host 'Press Enter to close'
    }
}

function Initialize-RunLog {
    $stateDir = Join-Path $internal 'current'
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir | Out-Null
    }
    $archiveDir = Join-Path $stateDir 'run_logs'
    if (-not (Test-Path -LiteralPath $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:transcriptArchivePath = Join-Path $archiveDir "run_$timestamp.log"
    $latestRunPath = Join-Path $stateDir 'latest_run.log'

    try {
        $script:transcriptPath = $latestRunPath
        "Tower Defense AI Audit Workflow log started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -LiteralPath $script:transcriptPath -Encoding UTF8
        "Archive copy: $script:transcriptArchivePath" | Add-Content -LiteralPath $script:transcriptPath -Encoding UTF8
    } catch {
        $script:transcriptPath = $script:transcriptArchivePath
        $script:transcriptArchivePath = $null
        "Tower Defense AI Audit Workflow log started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -LiteralPath $script:transcriptPath -Encoding UTF8
        "latest_run.log was locked, so this run is using the archive log path directly." | Add-Content -LiteralPath $script:transcriptPath -Encoding UTF8
    }

    Start-Transcript -Path $script:transcriptPath -Append | Out-Null
    $script:transcriptStarted = $true
    Write-Host "Full run log: $script:transcriptPath"
    if ($script:transcriptArchivePath) {
        Write-Host "Archived run log: $script:transcriptArchivePath"
    }
}

function Stop-RunLog {
    if ($script:transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
        }
        $script:transcriptStarted = $false
    }
    if ($script:transcriptPath -and $script:transcriptArchivePath -and (Test-Path -LiteralPath $script:transcriptPath)) {
        Copy-Item -LiteralPath $script:transcriptPath -Destination $script:transcriptArchivePath -Force
    }
}

function Write-RootStepSummary {
    param(
        [Parameter(Mandatory)][string] $Step,
        [Parameter(Mandatory)][string] $Status,
        [string] $Detail = ''
    )
    Write-Host ''
    Write-Host "STEP SUMMARY: $Step"
    Write-Host "  Status: $Status"
    if ($Detail.Trim().Length -gt 0) {
        Write-Host "  Detail: $Detail"
    }
    Write-Host ''
}

function Show-Menu {
    Write-Host ''
    Write-Host 'Tower Defense AI Audit Workflow'
    Write-Host ''
    Write-Host '1. Light audit + apply next safe improvement (~5 minutes + fix)'
    Write-Host '2. Light audit only (~5 minutes)'
    Write-Host '3. Deep audit + apply next safe improvement (~10 hours + fix)'
    Write-Host '4. Deep audit only (~10 hours / overnight)'
    Write-Host '5. Apply next queued fix/review'
    Write-Host '6. Cancel'
    Write-Host ''
    if ([Console]::IsInputRedirected) {
        return '__NO_INTERACTIVE_INPUT__'
    }
    return (Read-Host 'Choose 1-6 then press Enter (Enter = 1)')
}

function Show-NoInteractiveInputMessage {
    Write-Host ''
    Write-Host 'No interactive keyboard input is available, so no audit was started.'
    Write-Host 'Run this script from an interactive PowerShell window to use the menu, or choose an explicit command:'
    Write-Host ''
    Write-Host '  .\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Light'
    Write-Host '  .\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Deep'
    Write-Host '  .\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Light -AutoImprove'
    Write-Host '  .\_ai_audit_workflow\RUN_AUDIT.ps1 -NextFix'
    Write-Host ''
}

function Get-SafeLastExitCode {
    $lastExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $lastExit -or $null -eq $lastExit.Value) {
        return 0
    }
    return [int]$lastExit.Value
}

function Add-PreflightIssue {
    param(
        [string] $Title,
        [string] $Problem,
        [string] $Fix
    )
    $script:preflightIssues.Add([pscustomobject]@{
        title = $Title
        problem = $Problem
        fix = $Fix
    })
}

function Show-PreflightIssues {
    Write-Host ''
    Write-Host 'Preflight failed. Nothing was changed.'
    Write-Host ''
    foreach ($issue in $script:preflightIssues) {
        Write-Host "Problem: $($issue.title)"
        Write-Host "What happened: $($issue.problem)"
        Write-Host "How to fix it: $($issue.fix)"
        Write-Host ''
    }
}

function Get-RepoRootOrNull {
    try {
        return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    } catch {
        Add-PreflightIssue -Title 'Cannot find project folder' -Problem 'The workflow folder is not inside the tower defense Godot project folder.' -Fix 'Move _ai_audit_workflow back under C:\Users\donny\Desktop\tower_defense_godot, then run RUN_AUDIT.ps1 again.'
        return $null
    }
}

function Read-ConfigOrNull {
    $configPath = Join-Path $internal 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Add-PreflightIssue -Title 'Missing workflow config' -Problem "The file was not found: $configPath" -Fix 'Restore _ai_audit_workflow/_internal/config.json, then run the workflow again.'
        return $null
    }
    try {
        return Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    } catch {
        Add-PreflightIssue -Title 'Broken workflow config' -Problem "config.json could not be parsed as JSON. $($_.Exception.Message)" -Fix 'Open _ai_audit_workflow/_internal/config.json, fix the JSON syntax, then run the workflow again.'
        return $null
    }
}

function Test-AuditQueue {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)] $Config
    )
    $queuePath = Join-Path (Join-Path $RepoRoot $Config.currentDir) 'improvement_queue.json'
    if (-not (Test-Path -LiteralPath $queuePath)) {
        Add-PreflightIssue -Title 'No audit queue yet' -Problem "The next-fix queue does not exist: $queuePath" -Fix 'Choose 1 for Light audit or 2 for Deep audit first. After that finishes, choose 3 again.'
        return
    }
    try {
        $queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
        $queuedItems = @($queue.items | Where-Object { $_.status -eq 'queued' })
        if ($queuedItems.Count -eq 0) {
            Add-PreflightIssue -Title 'No queued fix or review prompt' -Problem 'The latest audit queue exists, but it does not contain a queued evidence-backed fix or review-backed polish prompt.' -Fix 'Run a fresh Light or Deep audit, or review the audit report for residual gaps that need manual evidence.'
        }
    } catch {
        Add-PreflightIssue -Title 'Broken audit queue' -Problem "The improvement queue could not be parsed: $queuePath. $($_.Exception.Message)" -Fix 'Run a fresh Light or Deep audit to rebuild the queue.'
    }
}

function Test-RepoCleanForApply {
    param([Parameter(Mandatory)][string] $RepoRoot)
    Push-Location $RepoRoot
    try {
        $status = @(git status --short)
        if ($status.Count -gt 0) {
            Add-PreflightIssue -Title 'Repo is dirty before applying a fix' -Problem "The apply-now path can edit files, but git status already has $($status.Count) row(s)." -Fix 'Review/preserve the current worktree first, or rerun with -AllowDirtyApply if applying into the dirty tree is intentional.'
        }
    } finally {
        Pop-Location
    }
}

function Test-AuditTierStopBudget {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][string] $AuditTier
    )
    $tierConfig = $Config.tiers.$AuditTier
    if ($null -eq $tierConfig) {
        Add-PreflightIssue -Title 'Missing audit tier config' -Problem "No config.json tier entry exists for $AuditTier." -Fix 'Restore or repair _ai_audit_workflow/_internal/config.json before running the audit.'
        return
    }
    if ([int]$tierConfig.timeoutSeconds -le 0) {
        Add-PreflightIssue -Title 'Audit stop budget is disabled' -Problem "$AuditTier timeoutSeconds is $($tierConfig.timeoutSeconds), which would allow an uncapped simulation run." -Fix 'Set a positive timeoutSeconds in _ai_audit_workflow/_internal/config.json, or run a narrower explicit command outside this workflow.'
    }
}

function Invoke-Preflight {
    param(
        [bool] $NeedsGodot,
        [bool] $NeedsCodex,
        [bool] $NeedsAuditQueue,
        [bool] $NeedsCleanApply = $false,
        [bool] $AllowDirtyApply = $false,
        [string] $AuditTier = ''
    )
    $script:preflightIssues.Clear()

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Add-PreflightIssue -Title 'PowerShell is too old' -Problem "This workflow needs Windows PowerShell 5 or newer. Current version: $($PSVersionTable.PSVersion)" -Fix 'Run it from normal Windows PowerShell on Windows 10/11, or install a newer PowerShell.'
    }

    $repoRoot = Get-RepoRootOrNull
    $config = Read-ConfigOrNull

    if ($null -ne $repoRoot) {
        $projectFile = Join-Path $repoRoot 'project.godot'
        if (-not (Test-Path -LiteralPath $projectFile)) {
            Add-PreflightIssue -Title 'Wrong folder' -Problem "project.godot was not found in $repoRoot" -Fix 'Run RUN_AUDIT.ps1 from C:\Users\donny\Desktop\tower_defense_godot\_ai_audit_workflow.'
        }
    }

    if ($NeedsGodot -and $null -ne $config) {
        if (-not (Test-Path -LiteralPath $config.godotExe)) {
            Add-PreflightIssue -Title 'Godot was not found' -Problem "The configured Godot executable does not exist: $($config.godotExe)" -Fix 'Install Godot 4.7 stable at that path, or update godotExe in _ai_audit_workflow/_internal/config.json.'
        }
        if ($AuditTier.Trim().Length -gt 0) {
            Test-AuditTierStopBudget -Config $config -AuditTier $AuditTier
        }
    }

    if ($NeedsCodex) {
        $codex = Get-Command codex -ErrorAction SilentlyContinue
        if ($null -eq $codex) {
            Add-PreflightIssue -Title 'Codex CLI was not found' -Problem 'The command `codex` is not available in this terminal path.' -Fix 'Open Codex normally or install/fix the Codex CLI, then reopen this launcher.'
        }
    }

    if ($NeedsAuditQueue -and $null -ne $repoRoot -and $null -ne $config) {
        Test-AuditQueue -RepoRoot $repoRoot -Config $config
    }

    if ($NeedsCleanApply -and -not $AllowDirtyApply -and $null -ne $repoRoot) {
        Test-RepoCleanForApply -RepoRoot $repoRoot
    }

    if ($script:preflightIssues.Count -gt 0) {
        Show-PreflightIssues
        return $false
    }
    return $true
}

function Invoke-PostAuditFixMenu {
    param([bool] $Interactive)
    if (-not $Interactive) {
        return 0
    }

    $repoRoot = Get-RepoRootOrNull
    $config = Read-ConfigOrNull
    if ($null -eq $repoRoot -or $null -eq $config) {
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'skipped' -Detail 'Could not read repo/config after audit.'
        return 0
    }

    $queuePath = Join-Path (Join-Path $repoRoot $config.currentDir) 'improvement_queue.json'
    if (-not (Test-Path -LiteralPath $queuePath)) {
        Write-Host ''
        Write-Host 'No improvement queue was produced.'
        Write-Host 'Check the latest run log and current status for the failed step.'
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'skipped' -Detail "Missing queue: $queuePath"
        return 0
    }

    try {
        $queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
        $items = @($queue.items | Where-Object { $_.status -eq 'queued' })
    } catch {
        Write-Host ''
        Write-Host "The improvement queue could not be read: $queuePath"
        Write-Host 'Run a fresh audit to rebuild it.'
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'failed' -Detail $_.Exception.Message
        return 1
    }

    if ($items.Count -eq 0) {
        Write-Host ''
        Write-Host 'No evidence-backed fixes or review-backed polish prompts were found by this audit.'
        Write-RootStepSummary -Step 'post-audit fix menu' -Status 'pass with gaps' -Detail '0 queued fix/review prompt(s).'
        return 0
    }

    Write-Host ''
    $codeCount = @($items | Where-Object { $_.lane -eq 'evidence-backed code fix' }).Count
    $reviewCount = @($items | Where-Object { $_.reviewBacked -eq $true }).Count
    Write-Host "Queued fixes/prompts found: $($items.Count) ($codeCount evidence-backed, $reviewCount review-backed)"
    foreach ($item in @($items | Select-Object -First 5)) {
        $lane = if ($null -ne $item.PSObject.Properties['lane']) { $item.lane } else { 'evidence-backed code fix' }
        Write-Host "- $($item.id): $($item.title) [$lane, $($item.area), score $($item.score)]"
    }
    if ($items.Count -gt 5) {
        Write-Host "- ...and $($items.Count - 5) more"
    }
    Write-Host ''
    Write-Host '1. Apply next fix/review now'
    Write-Host '2. Show next fix/review prompt only'
    Write-Host '3. Close'
    Write-Host ''
    $fixChoice = (Read-Host 'Choose 1-3').Trim()

    switch ($fixChoice) {
        '1' {
            if (-not (Invoke-Preflight -NeedsGodot $false -NeedsCodex $true -NeedsAuditQueue $true -NeedsCleanApply $true -AllowDirtyApply $AllowDirtyApply)) {
                Write-RootStepSummary -Step 'post-audit apply fix' -Status 'failed' -Detail 'Codex or queue preflight failed.'
                return 1
            }
            & (Join-Path $internal 'run_improvement_pass.ps1') -PrintPrompt -RunCodex -AllowDirtyApply:$AllowDirtyApply
            return (Get-SafeLastExitCode)
        }
        '2' {
            & (Join-Path $internal 'run_improvement_pass.ps1') -MenuPreview
            return (Get-SafeLastExitCode)
        }
        default {
            Write-Host 'Closed without applying a fix.'
            Write-RootStepSummary -Step 'post-audit fix menu' -Status 'skipped' -Detail 'User closed without applying a fix.'
            return 0
        }
    }
}

function Invoke-AutoImprovementLoop {
    param(
        [Parameter(Mandatory)][int] $MaxPasses,
        [bool] $AllowDirtyApply = $false
    )

    Write-Host ''
    Write-Host "Automatic improvement mode: up to $MaxPasses queued item(s)."
    Write-Host 'Each item must pass the Codex result contract and git diff --check.'

    $applied = 0
    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        $repoRoot = Get-RepoRootOrNull
        $config = Read-ConfigOrNull
        if ($null -eq $repoRoot -or $null -eq $config) {
            Write-RootStepSummary -Step 'automatic improvement loop' -Status 'failed' -Detail 'Could not read repo/config before checking the improvement queue.'
            return 1
        }
        $queuePath = Join-Path (Join-Path $repoRoot $config.currentDir) 'improvement_queue.json'
        if (-not (Test-Path -LiteralPath $queuePath)) {
            Write-RootStepSummary -Step 'automatic improvement loop' -Status 'passed with gaps' -Detail 'No improvement queue was produced; review findings.json and the latest run log.'
            return 0
        }
        $queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
        $queuedCount = @($queue.items | Where-Object { $_.status -eq 'queued' }).Count
        if ($queuedCount -eq 0) {
            Write-RootStepSummary -Step 'automatic improvement loop' -Status 'passed with gaps' -Detail 'No safe queued item is available; the audit remains diagnostic-only for this run.'
            return 0
        }

        $queueCheck = Invoke-Preflight -NeedsGodot $false -NeedsCodex $true -NeedsAuditQueue $true -NeedsCleanApply $true -AllowDirtyApply $AllowDirtyApply
        if (-not $queueCheck) {
            if ($applied -gt 0) {
                Write-RootStepSummary -Step 'automatic improvement loop' -Status 'passed with gaps' -Detail "$applied item(s) applied before the next item was blocked."
                return 0
            }
            Write-RootStepSummary -Step 'automatic improvement loop' -Status 'blocked' -Detail 'No safe queued item could be applied.'
            return 1
        }

        Write-Host "Applying queued improvement $pass of $MaxPasses..."
        & (Join-Path $internal 'run_improvement_pass.ps1') -PrintPrompt -RunCodex -AllowDirtyApply:$AllowDirtyApply
        $exitCode = Get-SafeLastExitCode
        if ($exitCode -ne 0) {
            Write-RootStepSummary -Step 'automatic improvement loop' -Status 'failed' -Detail "Improvement pass $pass failed with exit code $exitCode."
            return $exitCode
        }
        $applied++

        if (-not (Test-Path -LiteralPath $queuePath)) {
            break
        }
        $queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json
        $remaining = @($queue.items | Where-Object { $_.status -eq 'queued' }).Count
        if ($remaining -eq 0) {
            break
        }
    }

    Write-RootStepSummary -Step 'automatic improvement loop' -Status 'passed' -Detail "$applied queued item(s) applied. Re-run the audit to refresh evidence after these changes."
    return 0
}

$interactive = $PSBoundParameters.Count -eq 0
$pauseOnExitRequested = $interactive -or $PauseOnExit
Initialize-RunLog

if ($interactive) {
    $choice = (Show-Menu).Trim()
    switch ($choice) {
        '__NO_INTERACTIVE_INPUT__' {
            Show-NoInteractiveInputMessage
            Write-RootStepSummary -Step 'menu selection' -Status 'failed' -Detail 'No interactive keyboard input was available.'
            Stop-RunLog
            exit 1
        }
        '' { $Tier = 'Light'; $AutoImprove = $true }
        '1' { $Tier = 'Light'; $AutoImprove = $true }
        '2' { $Tier = 'Light' }
        '3' { $Tier = 'Deep'; $AutoImprove = $true }
        '4' { $Tier = 'Deep' }
        '5' { $NextFix = $true }
        '6' {
            Write-Host 'Cancelled.'
            Pause-IfInteractive -Interactive $pauseOnExitRequested
            Stop-RunLog
            exit 0
        }
        default {
            Write-Host "Invalid choice: $choice"
            Write-RootStepSummary -Step 'menu selection' -Status 'failed' -Detail "Invalid choice: $choice"
            Pause-IfInteractive -Interactive $pauseOnExitRequested
            Stop-RunLog
            exit 1
        }
    }
    if ($NextFix) {
        Write-Host 'Starting next fix/review prompt flow...'
    } elseif ($AutoImprove) {
        Write-Host "Starting $Tier audit with automatic improvement..."
    } else {
        Write-Host "Starting $Tier audit..."
    }
}

try {
    if ($NextFix) {
        if (-not (Invoke-Preflight -NeedsGodot $false -NeedsCodex $true -NeedsAuditQueue $true -NeedsCleanApply $true -AllowDirtyApply $AllowDirtyApply)) {
            Write-RootStepSummary -Step 'next fix preflight' -Status 'failed' -Detail 'No runnable evidence-backed fix or review-backed polish prompt is available.'
            Pause-IfInteractive -Interactive $pauseOnExitRequested
            exit 1
        }
        & (Join-Path $internal 'run_improvement_pass.ps1') -PrintPrompt -RunCodex -AllowDirtyApply:$AllowDirtyApply
        $exitCode = Get-SafeLastExitCode
        if ($exitCode -ne 0) {
            Write-Host "Workflow failed with exit code $exitCode."
        }
        Write-Host "Full run log saved: $script:transcriptPath"
        Pause-IfInteractive -Interactive $pauseOnExitRequested
        Stop-RunLog
        exit $exitCode
    }

    $auditTierForPreflight = if ($SkipAudit) { '' } else { $Tier }
    if (-not (Invoke-Preflight -NeedsGodot (-not $SkipAudit) -NeedsCodex $false -NeedsAuditQueue $false -AuditTier $auditTierForPreflight)) {
        Write-RootStepSummary -Step 'audit preflight' -Status 'failed' -Detail 'Audit prerequisites are missing.'
        Pause-IfInteractive -Interactive $pauseOnExitRequested
        exit 1
    }
    & (Join-Path $internal 'run_cycle.ps1') -Tier $Tier -SkipAudit:$SkipAudit -AllowDirtyQueue:$AllowDirtyQueue
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -eq 0) {
        if ($AutoImprove) {
            $autoImproveExitCode = Invoke-AutoImprovementLoop -MaxPasses $MaxFixes -AllowDirtyApply $AllowDirtyApply
            if ($autoImproveExitCode -ne 0) {
                $exitCode = $autoImproveExitCode
            }
        } elseif ($interactive -and -not $SkipAudit) {
            $postAuditExitCode = Invoke-PostAuditFixMenu -Interactive $interactive
            if ($postAuditExitCode -ne 0) {
                $exitCode = $postAuditExitCode
            }
        }
    }
    if ($exitCode -ne 0) {
        Write-Host "Workflow failed with exit code $exitCode."
    }
    Write-Host "Full run log saved: $script:transcriptPath"
    Pause-IfInteractive -Interactive $pauseOnExitRequested
    Stop-RunLog
    exit $exitCode
} catch {
    Write-Host ''
    Write-Host "Failed: $($_.Exception.Message)"
    Write-Host "Full run log saved: $script:transcriptPath"
    Pause-IfInteractive -Interactive $pauseOnExitRequested
    Stop-RunLog
    exit 1
}

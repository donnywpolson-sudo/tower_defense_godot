Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkflowRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '.')).Path
}

function Get-RepoRoot {
    if ((Split-Path -Leaf $PSScriptRoot) -eq '_internal') {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Read-WorkflowConfig {
    $path = Join-Path (Get-WorkflowRoot) 'config.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing workflow config: $path"
    }
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Ensure-WorkflowState {
    param([Parameter(Mandatory)] $Config)
    $stateDir = Join-Path (Get-RepoRoot) $Config.currentDir
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir | Out-Null
    }
    return $stateDir
}

function Assert-TowerDefenseRepo {
    $repoRoot = Get-RepoRoot
    $projectFile = Join-Path $repoRoot 'project.godot'
    if (-not (Test-Path -LiteralPath $projectFile)) {
        throw "project.godot was not found in repo root: $repoRoot"
    }
    $mainScene = Join-Path $repoRoot 'scenes\main.tscn'
    if (-not (Test-Path -LiteralPath $mainScene)) {
        throw "scenes/main.tscn was not found in repo root: $repoRoot"
    }
    return $repoRoot
}

function ConvertTo-JsonFile {
    param(
        [Parameter(Mandatory)] $Value,
        [Parameter(Mandatory)][string] $Path
    )
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-ShortGitStatus {
    param([Parameter(Mandatory)][string] $RepoRoot)
    Push-Location $RepoRoot
    try {
        return @(git status --short)
    } finally {
        Pop-Location
    }
}

function Invoke-RepoCommand {
    param(
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][scriptblock] $Command,
        [switch] $Quiet,
        [int] $FailureOutputLines = 40
    )
    Write-Host "==> $Label"
    $output = @()
    $global:LASTEXITCODE = 0
    if ($Quiet) {
        $output = @(& $Command 2>&1)
    } else {
        & $Command
    }
    $exitCode = Get-SafeLastExitCode
    if ($exitCode -ne 0) {
        if ($Quiet -and $output.Count -gt 0) {
            Write-Host "Captured output tail for failed step:"
            $output | Select-Object -Last $FailureOutputLines | ForEach-Object { Write-Host $_ }
        }
        throw "$Label failed with exit code $exitCode."
    }
}

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory)][string] $Argument)
    if ($Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }
    $escaped = $Argument -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Join-ProcessArguments {
    param([string[]] $ArgumentList)
    return (($ArgumentList | ForEach-Object { ConvertTo-ProcessArgument -Argument $_ }) -join ' ')
}

function Get-ChildProcessIds {
    param([Parameter(Mandatory)][int] $ParentProcessId)
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentProcessId" -ErrorAction SilentlyContinue)
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($child in $children) {
        $childId = [int]$child.ProcessId
        foreach ($descendantId in @(Get-ChildProcessIds -ParentProcessId $childId)) {
            $ids.Add([int]$descendantId)
        }
        $ids.Add($childId)
    }
    return @($ids.ToArray())
}

function Stop-ProcessTree {
    param([Parameter(Mandatory)][int] $RootProcessId)
    try {
        & taskkill.exe /PID $RootProcessId /T /F > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            return
        }
    } catch {
    }
    $ids = @((Get-ChildProcessIds -ParentProcessId $RootProcessId) + @($RootProcessId))
    foreach ($id in $ids) {
        try {
            $process = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($null -ne $process) {
                Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            }
        } catch {
        }
    }
}

function Invoke-RepoProcess {
    param(
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $ArgumentList,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [int] $TimeoutSeconds = 0,
        [string] $StdoutPath = '',
        [string] $StderrPath = '',
        [switch] $MirrorRunProgress
    )
    Write-Host "==> $Label"
    $workingDirectoryPath = ([string]$WorkingDirectory).Trim()
    if ($workingDirectoryPath.Length -eq 0) {
        throw "Working directory is empty for $Label."
    }
    $workingDirectoryPath = (Resolve-Path -LiteralPath $workingDirectoryPath).Path
    $useRedirectedProcess = ($StdoutPath.Trim().Length -gt 0 -or $StderrPath.Trim().Length -gt 0)
    $runnerPath = ''
    if ($StdoutPath.Trim().Length -gt 0) {
        $stdoutDir = Split-Path -Parent $StdoutPath
        if ($stdoutDir -and -not (Test-Path -LiteralPath $stdoutDir)) {
            New-Item -ItemType Directory -Path $stdoutDir | Out-Null
        }
    }
    if ($StderrPath.Trim().Length -gt 0) {
        $stderrDir = Split-Path -Parent $StderrPath
        if ($stderrDir -and -not (Test-Path -LiteralPath $stderrDir)) {
            New-Item -ItemType Directory -Path $stderrDir | Out-Null
        }
    }

    $mirrorsProgressFromOutput = $false
    if ($useRedirectedProcess) {
        if ($StdoutPath.Trim().Length -gt 0) {
            [System.IO.File]::WriteAllText($StdoutPath, '')
        }
        if ($StderrPath.Trim().Length -gt 0) {
            [System.IO.File]::WriteAllText($StderrPath, '')
        }
        $redirectDir = $workingDirectoryPath
        if ($StdoutPath.Trim().Length -gt 0) {
            $redirectDir = Split-Path -Parent $StdoutPath
        } elseif ($StderrPath.Trim().Length -gt 0) {
            $redirectDir = Split-Path -Parent $StderrPath
        }
        $runnerName = 'process_runner_{0}_{1}.cmd' -f $PID, ([datetime]::UtcNow.Ticks)
        $runnerPath = Join-Path $redirectDir $runnerName
        $commandLine = '"' + $FilePath + '" ' + (Join-ProcessArguments -ArgumentList $ArgumentList)
        if ($StdoutPath.Trim().Length -gt 0) {
            $commandLine += ' 1> "' + $StdoutPath + '"'
        }
        if ($StderrPath.Trim().Length -gt 0) {
            $commandLine += ' 2> "' + $StderrPath + '"'
        }
        @(
            '@echo off',
            'cd /d "' + $workingDirectoryPath + '"',
            $commandLine,
            'exit /b %ERRORLEVEL%'
        ) | Set-Content -LiteralPath $runnerPath -Encoding ASCII
        $startInfo = @{
            FilePath = $env:ComSpec
            ArgumentList = @('/d', '/c', $runnerPath)
            WorkingDirectory = $workingDirectoryPath
            Wait = $false
            PassThru = $true
            WindowStyle = 'Hidden'
        }
        $process = Start-Process @startInfo
    } else {
        $startInfo = @{
            FilePath = $FilePath
            ArgumentList = $ArgumentList
            WorkingDirectory = $workingDirectoryPath
            Wait = $false
            PassThru = $true
            WindowStyle = 'Hidden'
        }
        $process = Start-Process @startInfo
    }
    if ($TimeoutSeconds -gt 0) {
        $startedAt = Get-Date
        $timedOut = $false
        $mirroredProgressLineCount = 0
        while (-not $process.HasExited) {
            $elapsedSeconds = [int]((Get-Date) - $startedAt).TotalSeconds
            if ($elapsedSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                break
            }
            if ($MirrorRunProgress -and -not $mirrorsProgressFromOutput -and $StdoutPath.Trim().Length -gt 0 -and (Test-Path -LiteralPath $StdoutPath)) {
                try {
                    $progressLines = @(Get-Content -LiteralPath $StdoutPath | Where-Object {
                        $_ -match '^\s+\[[#-]{30}\]\s+\d+%\s+\|\s+\d+/\d+ runs\s+\|\s+elapsed\s+.+\s+\|\s+ETA\s+.+$'
                    })
                    if ($progressLines.Count -gt $mirroredProgressLineCount) {
                        $progressLines |
                            Select-Object -Skip $mirroredProgressLineCount |
                            ForEach-Object { Write-Host $_ }
                        $mirroredProgressLineCount = $progressLines.Count
                    }
                } catch {
                }
            }
            Start-Sleep -Seconds 1
            $process.Refresh()
        }
        if ($MirrorRunProgress -and -not $mirrorsProgressFromOutput -and $StdoutPath.Trim().Length -gt 0 -and (Test-Path -LiteralPath $StdoutPath)) {
            try {
                $progressLines = @(Get-Content -LiteralPath $StdoutPath | Where-Object {
                    $_ -match '^\s+\[[#-]{30}\]\s+\d+%\s+\|\s+\d+/\d+ runs\s+\|\s+elapsed\s+.+\s+\|\s+ETA\s+.+$'
                })
                if ($progressLines.Count -gt $mirroredProgressLineCount) {
                    $progressLines |
                        Select-Object -Skip $mirroredProgressLineCount |
                        ForEach-Object { Write-Host $_ }
                }
            } catch {
            }
        }
        if ($timedOut) {
            Stop-ProcessTree -RootProcessId $process.Id
            if ($runnerPath.Trim().Length -gt 0 -and (Test-Path -LiteralPath $runnerPath)) {
                try {
                    Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
                } catch {
                }
            }
            throw "$Label timed out after $TimeoutSeconds second(s)."
        }
    } else {
        $process.WaitForExit()
    }
    if ($useRedirectedProcess) {
        $process.WaitForExit()
    }
    $global:LASTEXITCODE = $process.ExitCode
    if ($runnerPath.Trim().Length -gt 0 -and (Test-Path -LiteralPath $runnerPath)) {
        try {
            Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
    if ($process.ExitCode -ne 0) {
        throw "$Label failed with exit code $($process.ExitCode)."
    }
}

function Get-SafeLastExitCode {
    $lastExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $lastExit -or $null -eq $lastExit.Value) {
        return 0
    }
    return [int]$lastExit.Value
}

function Write-StepSummary {
    param(
        [Parameter(Mandatory)][string] $Step,
        [Parameter(Mandatory)][string] $Status,
        [string] $LogPath = '',
        [string] $Detail = ''
    )
    Write-Host ''
    Write-Host "STEP SUMMARY: $Step"
    Write-Host "  Status: $Status"
    if ($LogPath.Trim().Length -gt 0) {
        Write-Host "  Log: $LogPath"
    }
    if ($Detail.Trim().Length -gt 0) {
        Write-Host "  Detail: $Detail"
    }
    Write-Host ''
}

function Get-ObjectProperty {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)][string] $Name,
        $Default = $null
    )
    if ($null -eq $Object) {
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $Default
    }
    return $prop.Value
}

function Read-JsonFileOrNull {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $raw = Get-Content -Raw -LiteralPath $Path
    if ($raw.Trim().Length -eq 0) {
        return $null
    }
    return $raw | ConvertFrom-Json
}

function Get-LatestFile {
    param(
        [Parameter(Mandatory)][string] $Folder,
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)][string] $Suffix,
        [datetime] $EarliestWriteTime = [datetime]::MinValue
    )
    if (-not (Test-Path -LiteralPath $Folder)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $_.Name.StartsWith($Prefix) -and $_.Name.EndsWith($Suffix) -and $_.LastWriteTime -ge $EarliestWriteTime } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-LatestSimulationPacket {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)] $Config,
        [datetime] $EarliestWriteTime = [datetime]::MinValue
    )
    $simDir = Join-Path $RepoRoot $Config.simulationDir
    $json = Get-LatestFile -Folder $simDir -Prefix 'ai_simulation_data_' -Suffix '.json' -EarliestWriteTime $EarliestWriteTime
    $report = Get-LatestFile -Folder $simDir -Prefix 'ai_simulation_report_' -Suffix '.md' -EarliestWriteTime $EarliestWriteTime
    $prompt = Get-LatestFile -Folder $simDir -Prefix 'ai_simulation_codex_prompt_' -Suffix '.md' -EarliestWriteTime $EarliestWriteTime
    return [pscustomobject]@{
        json = $json
        report = $report
        prompt = $prompt
        complete = ($null -ne $json -and $null -ne $report -and $null -ne $prompt)
    }
}

function Get-VisualReviewEvidence {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)] $Config,
        [datetime] $EarliestWriteTime = [datetime]::MinValue
    )
    $visualDir = Join-Path $RepoRoot $Config.visualReviewDir
    if (-not (Test-Path -LiteralPath $visualDir)) {
        return [pscustomobject]@{ folder = $visualDir; count = 0; newest = $null; files = @() }
    }
    $files = @(Get-ChildItem -LiteralPath $visualDir -File -Filter '*.png' |
        Where-Object { $_.LastWriteTime -ge $EarliestWriteTime } |
        Sort-Object LastWriteTime -Descending)
    $newest = if ($files.Count -gt 0) { $files[0].FullName } else { $null }
    return [pscustomobject]@{ folder = $visualDir; count = $files.Count; newest = $newest; files = @($files.FullName) }
}

function Test-GodotLogExpectedToken {
    param(
        [Parameter(Mandatory)][string] $LogPath,
        [Parameter(Mandatory)][string] $Expected
    )
    if (-not (Test-Path -LiteralPath $LogPath)) {
        return [pscustomobject]@{ passed = $false; detail = "Missing log: $LogPath" }
    }
    $text = Get-Content -Raw -LiteralPath $LogPath
    if ($text.Contains($Expected)) {
        return [pscustomobject]@{ passed = $true; detail = "Found expected token: $Expected" }
    }
    return [pscustomobject]@{ passed = $false; detail = "Expected token not found: $Expected" }
}

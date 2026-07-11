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

function Get-ProcessDiagnostics {
    param(
        [Parameter(Mandatory)][int] $RootProcessId,
        [int[]] $KnownProcessIds = @()
    )
    $ids = New-Object System.Collections.Generic.List[int]
    $ids.Add($RootProcessId)
    foreach ($id in $KnownProcessIds) {
        if (-not $ids.Contains([int]$id)) {
            $ids.Add([int]$id)
        }
    }
    foreach ($childId in @(Get-ChildProcessIds -ParentProcessId $RootProcessId)) {
        if (-not $ids.Contains([int]$childId)) {
            $ids.Add([int]$childId)
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($id in $ids) {
        $process = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            $rows.Add([pscustomobject]@{
                pid = [int]$id
                name = $null
                alive = $false
                exitCode = $null
                workingSetBytes = $null
                privateMemoryBytes = $null
                cpuSeconds = $null
            })
            continue
        }
        $exitCode = $null
        try {
            if ($process.HasExited) {
                $exitCode = $process.ExitCode
            }
        } catch {
        }
        $cpuSeconds = $null
        try {
            $cpuSeconds = [double]$process.TotalProcessorTime.TotalSeconds
        } catch {
        }
        $rows.Add([pscustomobject]@{
            pid = [int]$process.Id
            name = [string]$process.ProcessName
            alive = -not [bool]$process.HasExited
            exitCode = $exitCode
            workingSetBytes = [int64]$process.WorkingSet64
            privateMemoryBytes = [int64]$process.PrivateMemorySize64
            cpuSeconds = $cpuSeconds
        })
    }
    return @($rows.ToArray())
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
        [hashtable] $EnvironmentVariables = @{},
        [switch] $MirrorRunProgress,
        [switch] $ReturnResult
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

    $knownProcessIds = New-Object System.Collections.Generic.List[int]
    $maxWorkingSetBytes = [int64]0
    $maxPrivateMemoryBytes = [int64]0
    $maxCpuSeconds = [double]0
    $lastDiagnostics = @()
    $startedAt = Get-Date
    $timedOut = $false
    $launchError = $null
    $process = $null
    $mirrorsProgressFromOutput = $false
    try {
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
            $runnerLines = New-Object System.Collections.Generic.List[string]
            $runnerLines.Add('@echo off')
            foreach ($environmentKey in $EnvironmentVariables.Keys) {
                $environmentValue = [string]$EnvironmentVariables[$environmentKey]
                $runnerLines.Add(('set "{0}={1}"' -f $environmentKey, $environmentValue))
            }
            $runnerLines.Add('cd /d "' + $workingDirectoryPath + '"')
            $runnerLines.Add($commandLine)
            $runnerLines.Add('exit /b %ERRORLEVEL%')
            $runnerLines | Set-Content -LiteralPath $runnerPath -Encoding ASCII
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
    } catch {
        $launchError = $_.Exception.Message
        if (-not $ReturnResult) {
            throw
        }
    }

    if ($null -ne $process -and $TimeoutSeconds -gt 0) {
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
            $sample = @(Get-ProcessDiagnostics -RootProcessId $process.Id -KnownProcessIds @($knownProcessIds.ToArray()))
            foreach ($row in $sample) {
                if (-not $knownProcessIds.Contains([int]$row.pid)) {
                    $knownProcessIds.Add([int]$row.pid)
                }
                if ($null -ne $row.workingSetBytes) {
                    $maxWorkingSetBytes = [math]::Max($maxWorkingSetBytes, [int64]$row.workingSetBytes)
                }
                if ($null -ne $row.privateMemoryBytes) {
                    $maxPrivateMemoryBytes = [math]::Max($maxPrivateMemoryBytes, [int64]$row.privateMemoryBytes)
                }
                if ($null -ne $row.cpuSeconds) {
                    $maxCpuSeconds = [math]::Max($maxCpuSeconds, [double]$row.cpuSeconds)
                }
            }
            $lastDiagnostics = $sample
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
            if (-not $ReturnResult) {
                throw "$Label timed out after $TimeoutSeconds second(s)."
            }
        }
    } elseif ($null -ne $process) {
        $process.WaitForExit()
    }
    if ($null -ne $process -and $useRedirectedProcess) {
        $process.WaitForExit()
    }
    if ($null -ne $process) {
        $global:LASTEXITCODE = $process.ExitCode
        $lastDiagnostics = @(Get-ProcessDiagnostics -RootProcessId $process.Id -KnownProcessIds @($knownProcessIds.ToArray()))
    } else {
        $global:LASTEXITCODE = -1
    }
    $exitCode = if ($null -ne $process) { [int]$process.ExitCode } else { -1 }
    $durationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
    if ($runnerPath.Trim().Length -gt 0 -and (Test-Path -LiteralPath $runnerPath)) {
        try {
            Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
    $result = [pscustomobject]@{
        label = $Label
        succeeded = ($null -ne $process -and $exitCode -eq 0 -and -not $timedOut -and $null -eq $launchError)
        exitCode = $exitCode
        timedOut = $timedOut
        durationSeconds = $durationSeconds
        processId = if ($null -ne $process) { [int]$process.Id } else { $null }
        stdoutPath = $StdoutPath
        stderrPath = $StderrPath
        diagnostics = @($lastDiagnostics)
        maxWorkingSetBytes = $maxWorkingSetBytes
        maxPrivateMemoryBytes = $maxPrivateMemoryBytes
        maxCpuSeconds = $maxCpuSeconds
        launchError = $launchError
        capturedAt = (Get-Date).ToString('s')
    }
    if (-not $ReturnResult -and -not $result.succeeded) {
        if ($timedOut) {
            throw "$Label timed out after $TimeoutSeconds second(s)."
        }
        if ($null -ne $launchError) {
            throw "$Label could not start: $launchError"
        }
        throw "$Label failed with exit code $exitCode."
    }
    if ($ReturnResult) {
        return $result
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

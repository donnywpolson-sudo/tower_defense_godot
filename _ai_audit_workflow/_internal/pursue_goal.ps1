param(
    [Parameter(Mandatory)][string] $Goal,
    [switch] $DryRun,
    [switch] $ValidateOnly,
    [switch] $ApproveMutation,
    [switch] $ApproveExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Assert-TowerDefenseRepo
$config = Read-WorkflowConfig
$configGodotExe = [string]$config.godotExe
$goalsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '_ai_audit_workflow\goals'))
if ($Goal -notmatch '^[a-z0-9][a-z0-9_-]{0,63}$') { throw 'Goal must be a checked-in goal slug containing only lowercase letters, numbers, underscores, and hyphens.' }
$goalPath = [IO.Path]::GetFullPath((Join-Path $goalsRoot ($Goal + '.json')))
$goalsPrefix = $goalsRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $goalPath.StartsWith($goalsPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Goal contract escaped the checked-in goals directory.' }
if (-not (Test-Path -LiteralPath $goalPath -PathType Leaf)) { throw "Pursue-goal contract not found: $goalPath" }
$resolvedGoalPath = (Resolve-Path -LiteralPath $goalPath).Path
if (-not $resolvedGoalPath.StartsWith($goalsPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resolved goal contract escaped the checked-in goals directory.' }
$contract = Get-Content -Raw -LiteralPath $goalPath | ConvertFrom-Json
$allowedTypes = @('run_godot', 'run_godot_export', 'child_goal', 'assert_json', 'assert_latest_json', 'assert_file', 'mutate_json', 'protected_hashes', 'git_diff_check', 'process_clean')
$runnerScript = Join-Path $PSScriptRoot 'pursue_goal.ps1'

function Get-RelativePath {
    param([Parameter(Mandatory)][string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path.Contains(':')) { throw "Goal paths must be non-empty repo-relative paths: $Path" }
    $relative = ($Path -replace '/', '\\')
    $rootPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $candidate = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
    if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Goal path escaped the repository: $Path" }
    $existingPath = $candidate
    while (-not (Test-Path -LiteralPath $existingPath) -and -not [string]::IsNullOrWhiteSpace([IO.Path]::GetDirectoryName($existingPath))) {
        $existingPath = [IO.Path]::GetDirectoryName($existingPath)
    }
    $resolved = (Resolve-Path -LiteralPath $existingPath).Path
    if (-not ($resolved.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar).StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -and -not $resolved.Equals($rootPrefix.TrimEnd([IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved goal path or its nearest existing parent escaped the repository: $Path"
    }
    return $relative
}

function Get-GoalPathValue {
    param([Parameter(Mandatory)] $Object, [Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][ref] $Found)
    $current = $Object
    if ($Path.Trim().Length -eq 0) { $Found.Value = $true; return $current }
    foreach ($segment in ($Path.Trim('/') -split '/')) {
        if ($null -eq $current) { $Found.Value = $false; return $null }
        if ($current -is [System.Collections.IList] -and $current -isnot [string]) {
            $index = 0
            if (-not [int]::TryParse($segment, [ref]$index) -or $index -lt 0 -or $index -ge $current.Count) { $Found.Value = $false; return $null }
            $current = $current[$index]
            continue
        }
        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) { $Found.Value = $false; return $null }
        $current = $property.Value
    }
    $Found.Value = $true
    return $current
}

function Convert-ScalarForComparison {
    param($Value)
    if ($Value -is [bool]) { return ($(if ($Value) { 'true' } else { 'false' })) }
    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return ([double]$Value).ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
    return [string]$Value
}

function Test-ScalarEqual {
    param($Left, $Right)
    $numericTypes = @([int], [long], [double], [decimal], [float])
    if ($numericTypes -contains $Left.GetType() -and $numericTypes -contains $Right.GetType()) { return ([double]$Left -eq [double]$Right) }
    return ((Convert-ScalarForComparison $Left) -eq (Convert-ScalarForComparison $Right))
}

function Assert-JsonFile {
    param([Parameter(Mandatory)] $Stage)
    $relative = Get-RelativePath ([string]$Stage.file)
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "JSON assertion file is missing: $relative" }
    $value = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    foreach ($assertion in @($Stage.assertions)) {
        $found = $false
        $actual = Get-GoalPathValue -Object $value -Path ([string]$assertion.path) -Found ([ref]$found)
        if (-not $found) { throw "JSON assertion path is missing: $($assertion.path)" }
        if ($null -ne $assertion.PSObject.Properties['equals'] -and -not (Test-ScalarEqual $actual $assertion.equals)) { throw "JSON assertion failed at $($assertion.path): expected $($assertion.equals), got $actual" }
        if ($null -ne $assertion.PSObject.Properties['in']) {
            $matches = $false
            foreach ($candidate in @($assertion.in)) { if (Test-ScalarEqual $actual $candidate) { $matches = $true } }
            if (-not $matches) { throw "JSON assertion failed at $($assertion.path): value $actual is not allowed" }
        }
        if ($null -ne $assertion.PSObject.Properties['contains']) {
            if ($actual -is [string] -or $actual -isnot [System.Collections.IEnumerable]) { throw "JSON assertion at $($assertion.path) is not a collection" }
            $contains = $false
            foreach ($candidate in $actual) { if (Test-ScalarEqual $candidate $assertion.contains) { $contains = $true } }
            if (-not $contains) { throw "JSON assertion failed at $($assertion.path): collection does not contain $($assertion.contains)" }
        }
        if ($null -ne $assertion.PSObject.Properties['less_than_path']) {
            $otherFound = $false
            $other = Get-GoalPathValue -Object $value -Path ([string]$assertion.less_than_path) -Found ([ref]$otherFound)
            if (-not $otherFound -or [double]$actual -ge [double]$other) { throw "JSON assertion failed: $($assertion.path) is not less than $($assertion.less_than_path)" }
        }
    }
}

function Assert-LatestJson {
    param([Parameter(Mandatory)] $Stage)
    $relativeDirectory = Get-RelativePath ([string]$Stage.directory)
    $directory = Join-Path $repoRoot $relativeDirectory
    if (-not (Test-Path -LiteralPath $directory)) { throw "Latest JSON directory is missing: $relativeDirectory" }
    $prefix = [string]$Stage.prefix
    $suffix = [string]$Stage.suffix
    $latest = @(Get-ChildItem -LiteralPath $directory -File | Where-Object { $_.Name.StartsWith($prefix) -and $_.Name.EndsWith($suffix) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($latest.Count -ne 1) { throw "Expected one latest JSON packet matching $prefix*$suffix in $relativeDirectory" }
    $value = Get-Content -Raw -LiteralPath $latest[0].FullName | ConvertFrom-Json
    foreach ($assertion in @($Stage.assertions)) {
        $found = $false
        $actual = Get-GoalPathValue -Object $value -Path ([string]$assertion.path) -Found ([ref]$found)
        if (-not $found) { throw "Latest JSON assertion path is missing: $($assertion.path)" }
        if ($null -ne $assertion.PSObject.Properties['equals'] -and -not (Test-ScalarEqual $actual $assertion.equals)) { throw "Latest JSON assertion failed at $($assertion.path): expected $($assertion.equals), got $actual" }
        if ($null -ne $assertion.PSObject.Properties['contains']) {
            if ($actual -is [string] -or $actual -isnot [System.Collections.IEnumerable]) { throw "Latest JSON assertion at $($assertion.path) is not a collection" }
            $contains = $false
            foreach ($candidate in $actual) { if (Test-ScalarEqual $candidate $assertion.contains) { $contains = $true } }
            if (-not $contains) { throw "Latest JSON assertion failed at $($assertion.path): collection does not contain $($assertion.contains)" }
        }
        if ($null -ne $assertion.PSObject.Properties['greater_than']) {
            if ([double]$actual -le [double]$assertion.greater_than) { throw "Latest JSON assertion failed at $($assertion.path): expected > $($assertion.greater_than), got $actual" }
        }
    }
    return $latest[0].FullName
}

function Assert-File {
    param([Parameter(Mandatory)] $Stage)
    $relative = Get-RelativePath ([string]$Stage.file)
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required alpha artifact is missing: $relative" }
    return $path
}

function Get-Hashes {
    param([Parameter(Mandatory)] $Paths)
    $result = [ordered]@{}
    foreach ($relativeValue in @($Paths)) {
        $relative = Get-RelativePath ([string]$relativeValue)
        $path = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $path)) { throw "Protected file is missing: $relative" }
        $result[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return [pscustomobject]$result
}

function Test-ProtectedHashes {
    param([Parameter(Mandatory)] $Expected)
    foreach ($property in $Expected.PSObject.Properties) {
        $path = Join-Path $repoRoot $property.Name
        if (-not (Test-Path -LiteralPath $path)) { throw "Protected file disappeared: $($property.Name)" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne [string]$property.Value) { throw "Protected file changed: $($property.Name)" }
    }
}

function Format-JsonScalar {
    param($Value)
    if ($Value -is [bool]) { return ($(if ($Value) { 'true' } else { 'false' })) }
    if ($Value -is [string]) { return '"' + ([string]$Value).Replace('"', '\"') + '"' }
    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return ([double]$Value).ToString('0.############################', [Globalization.CultureInfo]::InvariantCulture) }
    return [string]$Value
}

function Invoke-JsonMutation {
    param([Parameter(Mandatory)] $Stage)
    $policy = $contract.mutation_policy
    $relative = Get-RelativePath ([string]$Stage.file)
    $allowedFiles = @($policy.allowed_files | ForEach-Object { Get-RelativePath ([string]$_) })
    $allowedPaths = @($policy.allowed_json_paths | ForEach-Object { [string]$_ })
    if ($allowedFiles -notcontains $relative) { throw "Mutation file is not allowlisted: $relative" }
    if ($allowedPaths -notcontains [string]$Stage.target_path) { throw "Mutation JSON path is not allowlisted: $($Stage.target_path)" }
    if (-not [bool]$policy.automatic) { throw 'Goal contract does not authorize automatic mutation.' }
    if (-not $DryRun -and -not $ApproveMutation) { throw 'Mutation stage requires explicit -ApproveMutation.' }
    $targetFile = Join-Path $repoRoot $relative
    $targetObject = Get-Content -Raw -LiteralPath $targetFile | ConvertFrom-Json
    $found = $false
    $current = Get-GoalPathValue -Object $targetObject -Path ([string]$Stage.target_path) -Found ([ref]$found)
    if (-not $found -or -not (Test-ScalarEqual $current $Stage.expected_current_value)) { throw "Mutation precondition failed at $($Stage.target_path): expected $($Stage.expected_current_value), got $current" }
    $sourceRelative = Get-RelativePath ([string]$Stage.source_file)
    $sourceObject = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $sourceRelative) | ConvertFrom-Json
    $sourceFound = $false
    $newValue = Get-GoalPathValue -Object $sourceObject -Path ([string]$Stage.source_path) -Found ([ref]$sourceFound)
    if (-not $sourceFound) { throw "Mutation source path is missing: $($Stage.source_path)" }
    if (-not (@($Stage.allowed_new_values) | Where-Object { Test-ScalarEqual $_ $newValue })) { throw "Selected mutation value is not allowlisted: $newValue" }
    if (-not (@($policy.allowed_values) | Where-Object { Test-ScalarEqual $_ $newValue })) { throw "Selected mutation value is not policy-allowlisted: $newValue" }
    if ($DryRun) { return "dry-run: would set $relative::$($Stage.target_path) from $current to $newValue" }
    $oldText = Format-JsonScalar $Stage.expected_current_value
    $newText = Format-JsonScalar $newValue
    $key = ([string]$Stage.target_path).Split('/')[-1]
    $pattern = '(?m)(?<prefix>"' + [regex]::Escape($key) + '"\s*:\s*)' + [regex]::Escape($oldText) + '(?<suffix>\s*[,}])'
    $raw = Get-Content -Raw -LiteralPath $targetFile
    $matches = [regex]::Matches($raw, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one scalar mutation match for $key, found $($matches.Count)" }
    $updated = [regex]::Replace($raw, $pattern, '${prefix}' + $newText + '${suffix}', 1)
    [IO.File]::WriteAllText($targetFile, $updated, (New-Object Text.UTF8Encoding($false)))
    $afterObject = Get-Content -Raw -LiteralPath $targetFile | ConvertFrom-Json
    $afterFound = $false
    $after = Get-GoalPathValue -Object $afterObject -Path ([string]$Stage.target_path) -Found ([ref]$afterFound)
    if (-not $afterFound -or -not (Test-ScalarEqual $after $newValue)) { throw "Mutation verification failed at $($Stage.target_path)" }
    return "set $relative::$($Stage.target_path) from $current to $newValue"
}

function Validate-Contract {
    if ($null -eq $contract -or $null -eq $contract.PSObject.Properties['goal_id']) { throw 'Goal contract is not an object with goal_id.' }
    if ($null -eq $contract.PSObject.Properties['objective']) { throw 'Goal contract is missing objective.' }
    if ($null -eq $contract.PSObject.Properties['mutation_policy']) { throw 'Goal contract is missing mutation_policy.' }
    if ([string]$contract.goal_id -notmatch '^[a-z0-9][a-z0-9_-]{0,63}$') { throw 'goal_id contains unsafe characters.' }
    if ($null -eq $contract.PSObject.Properties['stages'] -or @($contract.stages).Count -eq 0) { throw 'Goal contract must contain stages.' }
    foreach ($path in @($contract.protected_files) + @($contract.mutation_policy.allowed_files)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) { [void](Get-RelativePath ([string]$path)) }
    }
    $ids = @{}
    foreach ($stage in @($contract.stages)) {
        $id = [string]$stage.id
        if ($id.Trim().Length -eq 0 -or $ids.ContainsKey($id)) { throw "Goal stage IDs must be unique and non-empty: $id" }
        $ids[$id] = $true
        if ($allowedTypes -notcontains [string]$stage.type) { throw "Unsupported pursue-goal stage type: $($stage.type)" }
        if ($null -ne $stage.PSObject.Properties['timeout_seconds'] -and ([int]$stage.timeout_seconds -le 0 -or [int]$stage.timeout_seconds -gt 7200)) { throw "Stage timeout must be between 1 and 7200 seconds: $id" }
        foreach ($propertyName in @('file','directory','log','artifact','output','source_file')) {
            $property = $stage.PSObject.Properties[$propertyName]
            if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { [void](Get-RelativePath ([string]$property.Value)) }
        }
        if ([string]$stage.type -eq 'run_godot') {
            $script = [string]$stage.script
            if ($script -notmatch '^res://scripts/tools/[A-Za-z0-9_/-]+\.gd$' -or $script.Contains('..')) { throw "Godot stage script is outside res://scripts/tools: $script" }
            $scriptRelative = Get-RelativePath ($script.Substring(6))
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $scriptRelative) -PathType Leaf)) { throw "Godot stage script does not exist: $script" }
            if ([string]$stage.expected_token -notmatch '^[A-Z0-9][A-Z0-9_:-]{2,127}$') { throw "Godot stage expected_token is invalid: $id" }
        }
    }
    foreach ($stage in @($contract.stages | Where-Object { $_.type -eq 'mutate_json' })) {
        if (@($contract.mutation_policy.allowed_files) -notcontains [string]$stage.file) { throw "Mutation stage file is outside policy: $($stage.file)" }
        if (@($contract.mutation_policy.allowed_json_paths) -notcontains [string]$stage.target_path) { throw "Mutation stage path is outside policy: $($stage.target_path)" }
    }
    foreach ($stage in @($contract.stages | Where-Object { $_.type -eq 'child_goal' })) {
        if (@($contract.mutation_policy.allowed_child_goals) -notcontains [string]$stage.goal) { throw "Child goal is not delegated by the root policy: $($stage.goal)" }
    }
}

Validate-Contract
Write-Host "Pursue goal: $($contract.goal_id)"
Write-Host "Objective: $($contract.objective)"
if ($ValidateOnly) { Write-Host 'PURSUE_GOAL_CONTRACT_VALIDATION_OK'; exit 0 }

$stateDir = Join-Path $repoRoot '_ai_audit_workflow\_internal\current'
if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
$statePath = Join-Path $stateDir ("pursue_goal_{0}.json" -f $contract.goal_id)
$state = $null
if ((Test-Path -LiteralPath $statePath) -and -not $DryRun) { $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json }
if ($null -eq $state) {
    $state = [pscustomobject]@{
        schema_version = 1
        goal_id = [string]$contract.goal_id
        status = 'running'
        started_at = (Get-Date).ToString('s')
        goal_contract = (Resolve-Path -LiteralPath $goalPath).Path
        protected_file_hashes = Get-Hashes -Paths $contract.protected_files
        stages = @()
        mutations = @()
        artifacts = @()
        blocker = $null
        completed_at = $null
    }
}
if (-not $DryRun -and [string]$state.status -eq 'complete') {
    Write-Host 'PURSUE_GOAL_ALREADY_COMPLETE'
    Write-Host "State: $statePath"
    exit 0
}

function Save-State { if (-not $DryRun) { ConvertTo-JsonFile -Value $state -Path $statePath } }
function Get-StageResult([string]$Id) { return @($state.stages | Where-Object { $_.id -eq $Id } | Select-Object -First 1) }
function Set-StageResult {
    param([string]$Id,[string]$Status,[string]$Detail)
    $existing = @(Get-StageResult $Id)
    if ($existing.Count -gt 0) {
        $existing[0].status = $Status
        $existing[0].detail = $Detail
        $existing[0].completed_at = (Get-Date).ToString('s')
    } else {
        $state.stages += [pscustomobject]@{ id = $Id; status = $Status; detail = $Detail; completed_at = (Get-Date).ToString('s') }
    }
    Save-State
}

foreach ($stage in @($contract.stages)) {
    $existing = @(Get-StageResult ([string]$stage.id))
    if ($existing.Count -gt 0 -and $existing[0].status -in @('passed','reused','dry-run')) { Write-Host "SKIP $($stage.id): $($existing[0].status)"; continue }
    try {
        if (-not $DryRun -and [string]$stage.type -eq 'run_godot_export' -and -not $ApproveExport) {
            throw 'Export stage requires explicit -ApproveExport.'
        }
        if (-not $DryRun -and [string]$stage.type -eq 'mutate_json' -and -not $ApproveMutation) {
            throw 'Mutation stage requires explicit -ApproveMutation.'
        }
        switch ([string]$stage.type) {
            'run_godot' {
                $artifact = if ($null -ne $stage.PSObject.Properties['artifact']) { Join-Path $repoRoot (Get-RelativePath ([string]$stage.artifact)) } else { '' }
                $reuse = $null -ne $stage.PSObject.Properties['reuse_if_artifact_exists'] -and [bool]$stage.reuse_if_artifact_exists
                if ($reuse -and $artifact -and (Test-Path -LiteralPath $artifact)) { Set-StageResult ([string]$stage.id) 'reused' "reused existing artifact: $($stage.artifact)"; continue }
                if ($DryRun) { Set-StageResult ([string]$stage.id) 'dry-run' "dry-run: would run $($stage.script)"; continue }
                $logRelative = Get-RelativePath ([string]$stage.log)
                $logPath = Join-Path $repoRoot $logRelative
                $outPath = [IO.Path]::ChangeExtension($logPath, '.stdout.log')
                $errPath = [IO.Path]::ChangeExtension($logPath, '.stderr.log')
                $arguments = @('--headless','--no-header','--log-file',$logPath,'--path',$repoRoot,'--script',[string]$stage.script,'--') + @($stage.arguments | ForEach-Object { [string]$_ })
                $result = Invoke-RepoProcess -Label ([string]$stage.id) -FilePath $configGodotExe -ArgumentList $arguments -WorkingDirectory $repoRoot -TimeoutSeconds ([int]$stage.timeout_seconds) -StdoutPath $outPath -StderrPath $errPath -ReturnResult
                if (-not $result.succeeded) { throw "Godot stage failed with exit code $($result.exitCode)" }
                $combined = ((Get-Content -Raw -LiteralPath $outPath -ErrorAction SilentlyContinue) + (Get-Content -Raw -LiteralPath $logPath -ErrorAction SilentlyContinue))
                if (-not $combined.Contains([string]$stage.expected_token)) { throw "Expected token missing: $($stage.expected_token)" }
                Set-StageResult ([string]$stage.id) 'passed' "completed: $($stage.script)"
            }
            'child_goal' {
                if ($DryRun) { Set-StageResult ([string]$stage.id) 'dry-run' "dry-run: would pursue child goal $($stage.goal)"; continue }
                $shell = (Get-Command powershell.exe -ErrorAction Stop).Source
                $logRelative = Get-RelativePath ([string]$stage.log)
                $logPath = Join-Path $repoRoot $logRelative
                $outPath = [IO.Path]::ChangeExtension($logPath, '.stdout.log')
                $errPath = [IO.Path]::ChangeExtension($logPath, '.stderr.log')
                $childArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runnerScript,'-Goal',[string]$stage.goal,'-ApproveMutation:' + [string]$ApproveMutation,'-ApproveExport:' + [string]$ApproveExport)
                $result = Invoke-RepoProcess -Label ([string]$stage.id) -FilePath $shell -ArgumentList $childArgs -WorkingDirectory $repoRoot -TimeoutSeconds ([int]$stage.timeout_seconds) -StdoutPath $outPath -StderrPath $errPath -ReturnResult
                if (-not $result.succeeded) { throw "Child goal failed: $($stage.goal) (exit $($result.exitCode))" }
                Set-StageResult ([string]$stage.id) 'passed' "child goal complete: $($stage.goal)"
            }
            'run_godot_export' {
                if ($DryRun) { Set-StageResult ([string]$stage.id) 'dry-run' "dry-run: would export preset $($stage.preset)"; continue }
                $logRelative = Get-RelativePath ([string]$stage.log)
                $logPath = Join-Path $repoRoot $logRelative
                $outPath = [IO.Path]::ChangeExtension($logPath, '.stdout.log')
                $errPath = [IO.Path]::ChangeExtension($logPath, '.stderr.log')
                $outputRelative = Get-RelativePath ([string]$stage.output)
                $outputPath = Join-Path $repoRoot $outputRelative
                $outputDirectory = Split-Path -Parent $outputPath
                if (-not (Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null }
                $arguments = @('--headless','--no-header','--path',$repoRoot,'--export-release',[string]$stage.preset,$outputPath)
                $result = Invoke-RepoProcess -Label ([string]$stage.id) -FilePath $configGodotExe -ArgumentList $arguments -WorkingDirectory $repoRoot -TimeoutSeconds ([int]$stage.timeout_seconds) -StdoutPath $outPath -StderrPath $errPath -ReturnResult
                if (-not $result.succeeded) { throw "Alpha export failed with exit code $($result.exitCode)" }
                if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Alpha export completed without creating $outputRelative" }
                Set-StageResult ([string]$stage.id) 'passed' "alpha artifact created: $outputRelative"
            }
            'assert_json' { Assert-JsonFile $stage; Set-StageResult ([string]$stage.id) 'passed' 'all JSON assertions passed' }
            'assert_latest_json' {
                $latestPath = Assert-LatestJson $stage
                if (-not $DryRun) { $state.artifacts += [pscustomobject]@{ stage = [string]$stage.id; path = $latestPath; completed_at = (Get-Date).ToString('s') } }
                Set-StageResult ([string]$stage.id) 'passed' "latest packet validated: $latestPath"
            }
            'assert_file' { $path = Assert-File $stage; Set-StageResult ([string]$stage.id) 'passed' "required file exists: $path" }
            'mutate_json' {
                $detail = Invoke-JsonMutation $stage
                if (-not $DryRun) { $state.mutations += [pscustomobject]@{ file = [string]$stage.file; path = [string]$stage.target_path; detail = $detail; completed_at = (Get-Date).ToString('s') } }
                $mutationStatus = if ($DryRun) { 'dry-run' } else { 'passed' }
                Set-StageResult ([string]$stage.id) $mutationStatus $detail
            }
            'protected_hashes' { Test-ProtectedHashes -Expected $state.protected_file_hashes; Set-StageResult ([string]$stage.id) 'passed' 'protected files unchanged' }
            'git_diff_check' {
                if ($DryRun) { Set-StageResult ([string]$stage.id) 'dry-run' 'dry-run: would run git diff --check'; continue }
                Push-Location $repoRoot; try { & git diff --check; if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' } } finally { Pop-Location }
                Set-StageResult ([string]$stage.id) 'passed' 'git diff --check passed'
            }
            'process_clean' {
                if ($DryRun) { Set-StageResult ([string]$stage.id) 'dry-run' 'dry-run: would verify no Godot process remains'; continue }
                $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Godot(_v[0-9.]+-stable_win64)?$' })
                if ($running.Count -gt 0) { throw "Godot process cleanup failed: $($running.ProcessName -join ', ')" }
                Set-StageResult ([string]$stage.id) 'passed' 'no Godot processes remain'
            }
        }
    } catch {
        Set-StageResult ([string]$stage.id) 'failed' $_.Exception.Message
        $state.status = 'blocked'
        $state.blocker = [string]$_.Exception.Message
        $state.completed_at = (Get-Date).ToString('s')
        Save-State
        Write-Error "Pursue goal blocked at $($stage.id): $($_.Exception.Message)"
        exit 2
    }
}

if ($DryRun) { $state.status = 'dry_run'; Write-Host 'PURSUE_GOAL_DRY_RUN_OK' } else { $state.status = 'complete'; $state.completed_at = (Get-Date).ToString('s'); Write-Host 'PURSUE_GOAL_COMPLETE' }
Save-State
Write-Host "State: $statePath"
exit 0

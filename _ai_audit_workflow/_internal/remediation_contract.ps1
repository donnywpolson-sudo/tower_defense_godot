Set-StrictMode -Version Latest

function Read-StructuredRemediationResult {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $ExpectedFindingId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Codex did not write a result summary: $Path" }
    $text = Get-Content -Raw -LiteralPath $Path
    if ($text.Trim().Length -eq 0) { throw "Codex wrote an empty result summary: $Path" }
    try { $result = $text | ConvertFrom-Json } catch { throw "Codex result is not valid JSON: $($_.Exception.Message)" }
    if ([string]$result.findingId -ne $ExpectedFindingId) { throw 'Codex result findingId does not match the selected queue item.' }
    if ([string]$result.disposition -notin @('fixed','no_code_change','deferred')) { throw 'Codex result disposition must be fixed, no_code_change, or deferred.' }
    if ($null -eq $result.PSObject.Properties['filesChanged'] -or $result.filesChanged -isnot [System.Collections.IEnumerable] -or $result.filesChanged -is [string]) { throw 'Codex result filesChanged must be an array.' }
    if ([string]::IsNullOrWhiteSpace([string]$result.reason)) { throw 'Codex result reason must be non-empty.' }
    if ([string]$result.disposition -eq 'fixed' -and @($result.filesChanged).Count -eq 0) { throw 'A fixed result must declare changed files.' }
    if ([string]$result.disposition -ne 'fixed' -and @($result.filesChanged).Count -ne 0) { throw 'A non-fixed result cannot declare changed files.' }
    return $result
}

function Test-RemediationAllowedFile {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][object[]] $Patterns)
    $normalized = $Path.Replace('\','/')
    foreach ($pattern in $Patterns) {
        if ($normalized -like ([string]$pattern).Replace('\','/')) { return $true }
    }
    return $false
}

function Assert-RemediationDelta {
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $ActualChangedFiles,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $AllowedFiles
    )
    $actual = @($ActualChangedFiles | ForEach-Object { $_.Replace('\','/') } | Sort-Object -Unique)
    $declared = @($Result.filesChanged | ForEach-Object { ([string]$_).Replace('\','/') } | Sort-Object -Unique)
    if (@(Compare-Object -ReferenceObject $actual -DifferenceObject $declared).Count -ne 0) { throw "Declared filesChanged does not match the actual Codex delta. Actual: $($actual -join ', ')" }
    if ([string]$Result.disposition -eq 'deferred' -and $actual.Count -ne 0) { throw 'Deferred results cannot change files.' }
    if ([string]$Result.disposition -eq 'no_code_change' -and $actual.Count -ne 0) { throw 'no_code_change results cannot change files.' }
    if ([string]$Result.disposition -eq 'fixed') {
        if ($actual.Count -eq 0) { throw 'fixed results must create an actual repository delta.' }
        if ($AllowedFiles.Count -eq 0) { throw 'Fixed results require non-empty allowedFiles.' }
        foreach ($path in $actual) {
            if (-not (Test-RemediationAllowedFile -Path $path -Patterns $AllowedFiles)) { throw "Codex changed a file outside allowedFiles: $path" }
        }
    }
    return $actual
}

function Assert-RemediationValidatorSpec {
    param([Parameter(Mandatory)] $Item, [Parameter(Mandatory)][string] $RepoRoot)
    if ($null -eq $Item.PSObject.Properties['validator']) { throw 'Queue item is missing validator.' }
    $validator = $Item.validator
    $script = [string]$validator.script
    if ($script -notmatch '^res://scripts/tools/[A-Za-z0-9_/-]+\.gd$' -or $script.Contains('..')) { throw "Validator script is outside res://scripts/tools: $script" }
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $toolsRoot = [IO.Path]::GetFullPath((Join-Path $root 'scripts\tools')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $scriptPath = [IO.Path]::GetFullPath((Join-Path $root $script.Substring(6).Replace('/','\')))
    if (-not $scriptPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Validator script escaped scripts/tools: $script" }
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Validator script does not exist: $script" }
    $resolved = (Resolve-Path -LiteralPath $scriptPath).Path
    if (-not $resolved.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Resolved validator escaped scripts/tools: $script" }
    if ([string]$validator.expectedToken -notmatch '^[A-Z0-9][A-Z0-9_:-]{2,127}$') { throw 'Validator expectedToken is invalid.' }
    $timeout = [int]$validator.timeoutSeconds
    if ($timeout -le 0 -or $timeout -gt 7200) { throw 'Validator timeoutSeconds must be between 1 and 7200.' }
    return $validator
}

function Assert-FreshValidationToken {
    param(
        [Parameter(Mandatory)][string[]] $Paths,
        [Parameter(Mandatory)][string] $ExpectedToken,
        [Parameter(Mandatory)][DateTime] $StartedAt
    )
    $freshPaths = @($Paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Where-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc -ge $StartedAt.AddSeconds(-2) })
    if ($freshPaths.Count -eq 0) { throw 'Independent validator output was not fresh.' }
    $combined = ($freshPaths | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join [Environment]::NewLine
    if (-not $combined.Contains($ExpectedToken)) { throw "Independent validator did not emit fresh token $ExpectedToken." }
    return $freshPaths
}

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'pursue_goal.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

function Invoke-GoalValidationCase {
    param(
        [Parameter(Mandatory)][string] $Goal,
        [Parameter(Mandatory)][bool] $ShouldPass
    )

    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Goal $Goal -ValidateOnly 2>&1)
    $exitCode = [int]$LASTEXITCODE
    $ErrorActionPreference = $previousErrorPreference
    if ($ShouldPass -and $exitCode -ne 0) {
        throw "Expected goal '$Goal' to validate, but it exited $exitCode.`n$($output -join [Environment]::NewLine)"
    }
    if (-not $ShouldPass -and $exitCode -eq 0) {
        throw "Expected goal '$Goal' to be rejected."
    }
}

Invoke-GoalValidationCase -Goal 'frost_balance' -ShouldPass $true
Invoke-GoalValidationCase -Goal '..\frost_balance' -ShouldPass $false
Invoke-GoalValidationCase -Goal 'C:\outside\goal.json' -ShouldPass $false
Invoke-GoalValidationCase -Goal 'Uppercase' -ShouldPass $false

Write-Output 'WORKFLOW_SECURITY_VALIDATION_OK'

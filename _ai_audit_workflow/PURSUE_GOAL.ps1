param(
    [string] $Goal = 'hypothesis_to_alpha',
    [switch] $DryRun,
    [switch] $ValidateOnly,
    [switch] $ApproveMutation,
    [switch] $ApproveExport
)

$runner = Join-Path $PSScriptRoot '_internal\pursue_goal.ps1'
& $runner -Goal $Goal -DryRun:$DryRun -ValidateOnly:$ValidateOnly -ApproveMutation:$ApproveMutation -ApproveExport:$ApproveExport
$exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
exit $exitCode

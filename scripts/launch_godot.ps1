param(
    [string] $GodotExe = ''
)

$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = [Environment]::GetEnvironmentVariable('GODOT4_EXE')
}
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $localFallback = [IO.Path]::GetFullPath((Join-Path $projectRoot '..\Godot_v4.7-stable_win64.exe'))
    if (Test-Path -LiteralPath $localFallback -PathType Leaf) {
        $GodotExe = $localFallback
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $command = Get-Command godot4, godot -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        $GodotExe = $command.Source
    }
}

if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "Godot project root not found: $projectRoot"
}

if ([string]::IsNullOrWhiteSpace($GodotExe) -or -not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot executable not found. Pass -GodotExe, set GODOT4_EXE, or place the pinned executable beside the repository.'
}

Set-Location -LiteralPath $projectRoot
& $GodotExe --path $projectRoot

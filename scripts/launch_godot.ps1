$ErrorActionPreference = "Stop"

$projectRoot = "C:\Users\donny\Desktop\tower_defense_godot"
$godotExe = "C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe"

if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "Godot project root not found: $projectRoot"
}

if (-not (Test-Path -LiteralPath $godotExe -PathType Leaf)) {
    throw "Godot executable not found: $godotExe"
}

Set-Location -LiteralPath $projectRoot
& $godotExe --path $projectRoot

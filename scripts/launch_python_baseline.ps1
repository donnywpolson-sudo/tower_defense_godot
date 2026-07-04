$ErrorActionPreference = "Stop"

$pythonRoot = "C:\Users\donny\Desktop\tower_defense"
$entryPoint = Join-Path $pythonRoot "tower_defense.py"

if (-not (Test-Path -LiteralPath $pythonRoot -PathType Container)) {
    throw "Python baseline root not found: $pythonRoot"
}

if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
    throw "Python baseline entry point not found: $entryPoint"
}

Set-Location -LiteralPath $pythonRoot
python $entryPoint

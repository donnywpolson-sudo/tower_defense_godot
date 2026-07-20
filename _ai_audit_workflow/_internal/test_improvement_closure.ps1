param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'remediation_contract.ps1')

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('tower-defense-remediation-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixtureRoot)

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock] $Action, [Parameter(Mandatory)][string] $Label)
    try {
        & $Action
    } catch {
        return
    }
    throw "Expected rejection: $Label"
}

try {
    $validResultPath = Join-Path $fixtureRoot 'valid.json'
    '{"findingId":"F-1","disposition":"fixed","filesChanged":["scripts/game/example.gd"],"reason":"implemented"}' | Set-Content -LiteralPath $validResultPath -Encoding UTF8
    $valid = Read-StructuredRemediationResult -Path $validResultPath -ExpectedFindingId 'F-1'
    [void](Assert-RemediationDelta -Result $valid -ActualChangedFiles @('scripts/game/example.gd') -AllowedFiles @('scripts/game/*.gd'))

    $prosePath = Join-Path $fixtureRoot 'prose.txt'
    'Files changed: scripts/game/example.gd' | Set-Content -LiteralPath $prosePath -Encoding UTF8
    Assert-Throws -Label 'spoofed prose result' -Action { Read-StructuredRemediationResult -Path $prosePath -ExpectedFindingId 'F-1' }

    $falseNoChangePath = Join-Path $fixtureRoot 'false-no-change.json'
    '{"findingId":"F-1","disposition":"no_code_change","filesChanged":["scripts/game/example.gd"],"reason":"claimed no change"}' | Set-Content -LiteralPath $falseNoChangePath -Encoding UTF8
    Assert-Throws -Label 'no-change result declaring files' -Action { Read-StructuredRemediationResult -Path $falseNoChangePath -ExpectedFindingId 'F-1' }

    Assert-Throws -Label 'undeclared changed file' -Action { Assert-RemediationDelta -Result $valid -ActualChangedFiles @('scripts/game/example.gd','README.md') -AllowedFiles @('scripts/game/*.gd') }
    Assert-Throws -Label 'changed file outside allowlist' -Action { Assert-RemediationDelta -Result $valid -ActualChangedFiles @('scripts/game/example.gd') -AllowedFiles @('README.md') }
    Assert-Throws -Label 'fixed disposition without actual delta' -Action { Assert-RemediationDelta -Result $valid -ActualChangedFiles @() -AllowedFiles @('scripts/game/*.gd') }

    $noChange = [pscustomobject]@{ findingId = 'F-1'; disposition = 'no_code_change'; filesChanged = @(); reason = 'not reproducible' }
    [void](Assert-RemediationDelta -Result $noChange -ActualChangedFiles @() -AllowedFiles @())

    $validItem = [pscustomobject]@{ validator = [pscustomobject]@{ script = 'res://scripts/tools/run_remediation_validation.gd'; args = @(); expectedToken = 'REMEDIATION_VALIDATION_OK'; timeoutSeconds = 60 } }
    [void](Assert-RemediationValidatorSpec -Item $validItem -RepoRoot $repoRoot)
    $externalItem = [pscustomobject]@{ validator = [pscustomobject]@{ script = 'res://scripts/game/vertical_slice_game.gd'; args = @(); expectedToken = 'FAKE_OK'; timeoutSeconds = 60 } }
    Assert-Throws -Label 'external validator script' -Action { Assert-RemediationValidatorSpec -Item $externalItem -RepoRoot $repoRoot }

    $freshPath = Join-Path $fixtureRoot 'fresh.log'
    'REMEDIATION_VALIDATION_OK' | Set-Content -LiteralPath $freshPath -Encoding UTF8
    $startedAt = [DateTime]::UtcNow.AddSeconds(-1)
    [void](Assert-FreshValidationToken -Paths @($freshPath) -ExpectedToken 'REMEDIATION_VALIDATION_OK' -StartedAt $startedAt)
    Assert-Throws -Label 'missing expected token' -Action { Assert-FreshValidationToken -Paths @($freshPath) -ExpectedToken 'MISSING_TOKEN' -StartedAt $startedAt }
    (Get-Item -LiteralPath $freshPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-10)
    Assert-Throws -Label 'stale validation token' -Action { Assert-FreshValidationToken -Paths @($freshPath) -ExpectedToken 'REMEDIATION_VALIDATION_OK' -StartedAt ([DateTime]::UtcNow) }

    Write-Output 'IMPROVEMENT_CLOSURE_VALIDATION_OK'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedFixture)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hookPath = Join-Path $repoRoot '.githooks\pre-commit'
if (-not (Test-Path -LiteralPath $hookPath)) {
  throw "Pre-commit hook was not found: $hookPath"
}

& git -C $repoRoot config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to configure the repository Git hooks path.'
}

$configuredPath = (& git -C $repoRoot config --get core.hooksPath).Trim()
if ($configuredPath -ne '.githooks') {
  throw "Unexpected Git hooks path: $configuredPath"
}

Write-Host 'Git pre-commit test gate installed.' -ForegroundColor Green

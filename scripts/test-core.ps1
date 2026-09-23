param(
  [string]$DevEcoSdkHome = 'D:\DevEco Studio\sdk',
  [string]$JavaHome = 'D:\DevEco Studio\jbr',
  [string]$NodePath = 'D:\DevEco Studio\tools\node\node.exe',
  [string]$HvigorPath = 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.js'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $repoRoot

foreach ($path in @($DevEcoSdkHome, $JavaHome, $NodePath, $HvigorPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Required test tool was not found: $path" }
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'oh_modules\@ohos\hypium'))) {
  throw 'Test dependency @ohos/hypium is missing. Run: D:\DevEco Studio\tools\ohpm\bin\ohpm.bat install'
}

$env:DEVECO_SDK_HOME = $DevEcoSdkHome
$env:JAVA_HOME = $JavaHome
$env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
$previousTestRunning = $env:PALMKEEP_CORE_TEST_RUNNING
try {
  $env:PALMKEEP_CORE_TEST_RUNNING = '1'
  & $NodePath $HvigorPath --no-daemon --mode module -p product=default -p buildMode=debug test
  if ($LASTEXITCODE -ne 0) { throw 'Core unit tests failed.' }
} finally {
  if ($null -eq $previousTestRunning) {
    Remove-Item Env:PALMKEEP_CORE_TEST_RUNNING -ErrorAction SilentlyContinue
  } else {
    $env:PALMKEEP_CORE_TEST_RUNNING = $previousTestRunning
  }
}

$resultPath = Join-Path $repoRoot 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
if (-not (Test-Path -LiteralPath $resultPath)) { throw 'Core unit test result was not generated.' }
$summary = Get-Content -Encoding UTF8 $resultPath | Where-Object { $_ -like 'Tests run:*' } | Select-Object -Last 1
if (-not $summary -or $summary -notmatch 'Failure: 0, Error: 0') {
  throw "Core unit test result is incomplete or contains failures: $summary"
}
Write-Host "Core unit tests passed. $summary" -ForegroundColor Green

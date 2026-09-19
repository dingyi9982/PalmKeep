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

foreach ($path in @($JavaHome, $NodePath, $HvigorPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required build tool was not found: $path"
  }
}

$jsonFiles = @(
  'AppScope\app.json5',
  'oh-package.json5',
  'entry\oh-package.json5',
  'entry\src\main\resources\base\element\string.json',
  'entry\src\main\resources\base\element\color.json'
)
foreach ($relativePath in $jsonFiles) {
  $path = Join-Path $repoRoot $relativePath
  Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json | Out-Null
}

$env:DEVECO_SDK_HOME = $DevEcoSdkHome
$env:JAVA_HOME = $JavaHome
$env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
& $NodePath $HvigorPath --no-daemon --mode module -p product=default -p buildMode=debug assembleHap
if ($LASTEXITCODE -ne 0) {
  throw 'Debug preflight build failed.'
}
Write-Host 'Preflight passed.' -ForegroundColor Green

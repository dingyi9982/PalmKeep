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
$requiredCompatibleSdk = '5.0.0(12)'
$requiredMinApiVersion = 50000012

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

$buildProfilePath = Join-Path $repoRoot 'build-profile.json5'
if (-not (Test-Path -LiteralPath $buildProfilePath)) {
  throw 'build-profile.json5 was not found. Configure the project before building.'
}
$buildProfile = Get-Content -Raw -Encoding UTF8 $buildProfilePath | ConvertFrom-Json
$incompatibleProducts = @($buildProfile.app.products | Where-Object {
  [string]$_.compatibleSdkVersion -ne $requiredCompatibleSdk
})
if ($incompatibleProducts.Count -gt 0) {
  $names = @($incompatibleProducts | ForEach-Object { [string]$_.name }) -join ', '
  throw "Products [$names] must use compatibleSdkVersion $requiredCompatibleSdk for HarmonyOS 5.0 support."
}

$env:DEVECO_SDK_HOME = $DevEcoSdkHome
$env:JAVA_HOME = $JavaHome
$env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
& $NodePath $HvigorPath --no-daemon --mode module -p product=default -p buildMode=debug assembleHap
if ($LASTEXITCODE -ne 0) {
  throw 'Debug preflight build failed.'
}
$mergedProfilePath = Join-Path $repoRoot 'entry\build\default\intermediates\merge_profile\default\module.json'
if (-not (Test-Path -LiteralPath $mergedProfilePath)) {
  throw 'The merged module profile was not generated.'
}
$mergedProfile = Get-Content -Raw -Encoding UTF8 $mergedProfilePath | ConvertFrom-Json
if ([int]$mergedProfile.app.minAPIVersion -ne $requiredMinApiVersion) {
  throw "Built HAP minAPIVersion is $($mergedProfile.app.minAPIVersion), expected $requiredMinApiVersion."
}
Write-Host 'Preflight passed.' -ForegroundColor Green

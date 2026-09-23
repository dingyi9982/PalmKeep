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
$requiredTargetSdk = '6.0.1(21)'
$requiredMinApiVersion = 50000012
$requiredTargetApiVersion = 60001021
$requiredBundleName = 'com.palmvault.app'

foreach ($path in @($JavaHome, $NodePath, $HvigorPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required build tool was not found: $path"
  }
}

& (Join-Path $PSScriptRoot 'check-text-encoding.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Text encoding check failed.' }
& $NodePath (Join-Path $PSScriptRoot 'release-metadata-regression.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Release metadata regression check failed.' }

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
$requiredProducts = @('default', 'localRelease', 'debug')
$configuredProducts = @($buildProfile.app.products | ForEach-Object { [string]$_.name })
foreach ($productName in $requiredProducts) {
  if ($configuredProducts -notcontains $productName) {
    throw "build-profile.json5 is missing the required product '$productName'."
  }
}
$incompatibleProducts = @($buildProfile.app.products | Where-Object {
  [string]$_.compatibleSdkVersion -ne $requiredCompatibleSdk
})
if ($incompatibleProducts.Count -gt 0) {
  $names = @($incompatibleProducts | ForEach-Object { [string]$_.name }) -join ', '
  throw "Products [$names] must use compatibleSdkVersion $requiredCompatibleSdk for HarmonyOS 5.0 support."
}
$wrongTargetProducts = @($buildProfile.app.products | Where-Object {
  [string]$_.targetSdkVersion -ne $requiredTargetSdk
})
if ($wrongTargetProducts.Count -gt 0) {
  $names = @($wrongTargetProducts | ForEach-Object { [string]$_.name }) -join ', '
  throw "Products [$names] must use targetSdkVersion $requiredTargetSdk."
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
if ([int]$mergedProfile.app.targetAPIVersion -ne $requiredTargetApiVersion) {
  throw "Built HAP targetAPIVersion is $($mergedProfile.app.targetAPIVersion), expected $requiredTargetApiVersion."
}
if ([string]$mergedProfile.app.bundleName -ne $requiredBundleName) {
  throw "Built HAP bundleName is $($mergedProfile.app.bundleName), expected $requiredBundleName."
}
Write-Host 'Preflight passed.' -ForegroundColor Green

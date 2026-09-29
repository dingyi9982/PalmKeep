param(
  [Parameter(Mandatory = $true)]
  [string]$AppPath,
  [Parameter(Mandatory = $true)]
  [string]$ExpectedVersionName,
  [Parameter(Mandatory = $true)]
  [int]$ExpectedVersionCode,
  [string]$ExpectedBundleName = 'com.palmkeep.app',
  [int]$ExpectedCompatibleApi = 12,
  [int]$ExpectedTargetApi = 21,
  [string]$DevEcoSdkHome = 'D:\DevEco Studio\sdk',
  [string]$JavaHome = 'D:\DevEco Studio\jbr'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resolvedAppPath = (Resolve-Path -LiteralPath $AppPath).Path
if ([IO.Path]::GetExtension($resolvedAppPath) -ne '.app') {
  throw "Release artifact must be an .app package: $resolvedAppPath"
}

$javaPath = Join-Path $JavaHome 'bin\java.exe'
$signToolPath = Join-Path $DevEcoSdkHome 'default\openharmony\toolchains\lib\hap-sign-tool.jar'
foreach ($requiredPath in @($javaPath, $signToolPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Release verification tool was not found: $requiredPath"
  }
}

$temporaryPrefix = 'palmkeep-release-verify-'
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryDirectory = Join-Path $temporaryRoot ($temporaryPrefix + [Guid]::NewGuid().ToString('N'))
$certificatePath = Join-Path $temporaryDirectory 'certificate-chain.cer'
$profilePath = Join-Path $temporaryDirectory 'profile.p7b'
$profileResultPath = Join-Path $temporaryDirectory 'profile-result.json'
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
  # Windows PowerShell 5.1 does not load the assembly that defines ZipArchive
  # when only System.IO.Compression.FileSystem is requested.
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $appStream = [IO.File]::OpenRead($resolvedAppPath)
  $appArchive = [IO.Compression.ZipArchive]::new($appStream, [IO.Compression.ZipArchiveMode]::Read)
  try {
    $packEntry = $appArchive.GetEntry('pack.info')
    if ($null -eq $packEntry) { throw 'Release APP does not contain pack.info.' }
    $reader = [IO.StreamReader]::new($packEntry.Open(), [Text.Encoding]::UTF8)
    try { $packInfo = $reader.ReadToEnd() | ConvertFrom-Json }
    finally { $reader.Dispose() }

    $summary = $packInfo.summary.app
    if ([string]$summary.bundleName -ne $ExpectedBundleName) {
      throw "Release APP bundleName is $($summary.bundleName), expected $ExpectedBundleName."
    }
    if ([string]$summary.version.name -ne $ExpectedVersionName -or
      [int]$summary.version.code -ne $ExpectedVersionCode) {
      throw "Release APP version is $($summary.version.name) ($($summary.version.code)), " +
        "expected $ExpectedVersionName ($ExpectedVersionCode)."
    }
    $modules = @($packInfo.summary.modules)
    if ($modules.Count -eq 0) { throw 'Release APP does not contain any modules.' }
    foreach ($module in $modules) {
      if ([int]$module.apiVersion.compatible -ne $ExpectedCompatibleApi -or
        [int]$module.apiVersion.target -ne $ExpectedTargetApi) {
        throw "Release APP module $($module.distro.moduleName) uses API " +
          "$($module.apiVersion.compatible)/$($module.apiVersion.target), expected " +
          "$ExpectedCompatibleApi/$ExpectedTargetApi."
      }
    }

    $hapEntries = @($appArchive.Entries | Where-Object { $_.FullName.EndsWith('.hap') })
    if ($hapEntries.Count -eq 0) { throw 'Release APP does not contain a HAP module.' }
    for ($index = 0; $index -lt $hapEntries.Count; $index += 1) {
      $hapPath = Join-Path $temporaryDirectory "module-$index.hap"
      $hapStream = [IO.File]::Create($hapPath)
      try {
        $entryStream = $hapEntries[$index].Open()
        try { $entryStream.CopyTo($hapStream) }
        finally { $entryStream.Dispose() }
      } finally { $hapStream.Dispose() }
      $nestedStream = [IO.File]::OpenRead($hapPath)
      $nestedArchive = [IO.Compression.ZipArchive]::new($nestedStream, [IO.Compression.ZipArchiveMode]::Read)
      try {
        $debugEntries = @($nestedArchive.Entries | Where-Object {
          $_.FullName -like '*palmkeep_demo*'
        })
        if ($debugEntries.Count -gt 0) {
          throw 'Release APP contains Debug screenshot demo assets.'
        }
      } finally {
        $nestedArchive.Dispose()
        $nestedStream.Dispose()
      }
    }
  } finally {
    $appArchive.Dispose()
    $appStream.Dispose()
  }

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $signatureOutput = @(& $javaPath -jar $signToolPath verify-app -inFile $resolvedAppPath -inForm zip `
      -outCertChain $certificatePath -outProfile $profilePath 2>&1)
    $signatureExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($signatureExitCode -ne 0) {
    $signatureOutput | ForEach-Object { Write-Host $_ }
    throw 'Release APP signature verification failed.'
  }
  $ErrorActionPreference = 'Continue'
  try {
    $profileOutput = @(& $javaPath -jar $signToolPath verify-profile -inFile $profilePath `
      -outFile $profileResultPath 2>&1)
    $profileExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($profileExitCode -ne 0) {
    $profileOutput | ForEach-Object { Write-Host $_ }
    throw 'Release APP Profile verification failed.'
  }

  $profileResult = Get-Content -Raw -Encoding UTF8 $profileResultPath | ConvertFrom-Json
  if (-not [bool]$profileResult.verifiedPassed) { throw 'Release APP Profile did not pass verification.' }
  $content = $profileResult.content
  if ([string]$content.type -ne 'release') {
    throw "Release APP uses a $($content.type) Profile instead of a release Profile."
  }
  if ([string]$content.'app-distribution-type' -ne 'app_gallery') {
    throw "Release APP distribution type is $($content.'app-distribution-type'), expected app_gallery."
  }
  if ([string]$content.'bundle-info'.'bundle-name' -ne $ExpectedBundleName) {
    throw "Release Profile bundleName is $($content.'bundle-info'.'bundle-name'), expected $ExpectedBundleName."
  }
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $notBefore = [long]$content.validity.'not-before'
  $notAfter = [long]$content.validity.'not-after'
  if ($now -lt $notBefore -or $now -ge $notAfter) {
    throw 'Release signing Profile is not currently valid.'
  }
  $verificationMessage = "Release APP verified: $ExpectedBundleName $ExpectedVersionName " +
    "($ExpectedVersionCode), release/app_gallery Profile."
  Write-Host $verificationMessage -ForegroundColor Green
} finally {
  if (Test-Path -LiteralPath $temporaryDirectory) {
    $resolvedTemporaryDirectory = (Resolve-Path -LiteralPath $temporaryDirectory).Path
    $temporaryLeaf = [IO.Path]::GetFileName($resolvedTemporaryDirectory)
    if ($resolvedTemporaryDirectory.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
      $temporaryLeaf.StartsWith($temporaryPrefix, [StringComparison]::Ordinal)) {
      Remove-Item -LiteralPath $resolvedTemporaryDirectory -Recurse -Force
    } else {
      Write-Warning "Refusing to remove unexpected verification directory: $resolvedTemporaryDirectory"
    }
  }
}

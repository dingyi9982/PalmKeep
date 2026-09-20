param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$VersionName,
  [int]$VersionCode = 0,
  [switch]$NoPush,
  [string]$DevEcoSdkHome = 'D:\DevEco Studio\sdk',
  [string]$JavaHome = 'D:\DevEco Studio\jbr',
  [string]$NodePath = 'D:\DevEco Studio\tools\node\node.exe',
  [string]$HvigorPath = 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.js'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $repoRoot
$appProfilePath = Join-Path $repoRoot 'AppScope\app.json5'
$versionScript = Join-Path $PSScriptRoot 'release-version.ps1'
$preflightScript = Join-Path $PSScriptRoot 'preflight.ps1'
$versionFiles = @('AppScope/app.json5', 'oh-package.json5', 'entry/oh-package.json5')
$tagName = "v$VersionName"
$releaseDirectory = Join-Path $repoRoot 'release'
$powerShellPath = (Get-Process -Id $PID).Path
$prepared = $false
$committed = $false
$tagged = $false

function Invoke-Git {
  param([string[]]$Arguments)
  $output = @(& git -C $repoRoot @Arguments)
  if ($LASTEXITCODE -ne 0) {
    throw "Git command failed: git $($Arguments -join ' ')"
  }
  return $output
}

function Assert-CleanRepository {
  $status = @(Invoke-Git @('status', '--porcelain', '--untracked-files=all'))
  if ($status.Count -gt 0) {
    throw "The repository must be clean before release:`n$($status -join "`n")"
  }
}

function Invoke-CheckedScript {
  param([string]$Path, [string[]]$Arguments)
  & $powerShellPath -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "PowerShell script failed: $Path"
  }
}

try {
  if ($VersionName -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw "VersionName '$VersionName' is invalid. Expected x.y.z."
  }
  Assert-CleanRepository
  $branch = [string](Invoke-Git @('symbolic-ref', '--quiet', '--short', 'HEAD'))
  if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'A release cannot be created from a detached HEAD.'
  }
  & git -C $repoRoot rev-parse --quiet --verify "refs/tags/$tagName" *> $null
  if ($LASTEXITCODE -eq 0) {
    throw "Tag $tagName already exists."
  }
  $profileBeforeRelease = Get-Content -Raw -Encoding UTF8 $appProfilePath | ConvertFrom-Json
  $versionsBeforeRelease = @(
    [string]$profileBeforeRelease.app.versionName,
    [string]((Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'oh-package.json5') | ConvertFrom-Json).version),
    [string]((Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'entry\oh-package.json5') | ConvertFrom-Json).version)
  )
  $versionAlreadyPrepared = @($versionsBeforeRelease | Where-Object { $_ -ne $VersionName }).Count -eq 0

  Write-Host '1/6 Running preflight...'
  Invoke-CheckedScript -Path $preflightScript -Arguments @(
    '-DevEcoSdkHome', $DevEcoSdkHome, '-JavaHome', $JavaHome,
    '-NodePath', $NodePath, '-HvigorPath', $HvigorPath
  )
  Assert-CleanRepository

  if ($versionAlreadyPrepared) {
    if ($VersionCode -gt 0 -and $VersionCode -ne [int]$profileBeforeRelease.app.versionCode) {
      throw "VersionCode $VersionCode does not match the prepared versionCode $($profileBeforeRelease.app.versionCode)."
    }
    Write-Host "2/6 Version $VersionName is already prepared; using the current clean commit."
  } else {
    Write-Host "2/6 Preparing version $VersionName..."
    $versionArguments = @('-Action', 'Prepare', '-VersionName', $VersionName)
    if ($VersionCode -gt 0) { $versionArguments += @('-VersionCode', [string]$VersionCode) }
    Invoke-CheckedScript -Path $versionScript -Arguments $versionArguments
    $prepared = $true

    $changedFiles = @(Invoke-Git @('status', '--porcelain') | ForEach-Object { $_.Substring(3).Trim('"').Replace('\', '/') })
    $unexpected = @($changedFiles | Where-Object { $versionFiles -notcontains $_ })
    if ($unexpected.Count -gt 0 -or $changedFiles -notcontains 'AppScope/app.json5') {
      throw "Unexpected version changes. Changed: $($changedFiles -join ', ')"
    }
    $appVersion = [string]((Get-Content -Raw -Encoding UTF8 $appProfilePath | ConvertFrom-Json).app.versionName)
    $rootPackageVersion = [string]((Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'oh-package.json5') | ConvertFrom-Json).version)
    $entryPackageVersion = [string]((Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'entry\oh-package.json5') | ConvertFrom-Json).version)
    $actualVersions = @($appVersion, $rootPackageVersion, $entryPackageVersion)
    if (@($actualVersions | Where-Object { $_ -ne $VersionName }).Count -gt 0) {
      throw "Version files do not all contain $VersionName."
    }
    Invoke-Git @('diff', '--check') | Out-Null

    Invoke-Git (@('add', '--') + $versionFiles) | Out-Null
    Invoke-Git @('commit', '-m', "发布 $VersionName 版本") | Out-Null
    $committed = $true
    Assert-CleanRepository
  }

  Write-Host '3/6 Creating release tag...'
  Invoke-CheckedScript -Path $versionScript -Arguments @('-Action', 'Tag')
  $tagged = $true

  Write-Host '4/6 Building signed Release HAP...'
  $env:DEVECO_SDK_HOME = $DevEcoSdkHome
  $env:JAVA_HOME = $JavaHome
  $env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
  & $NodePath $HvigorPath --no-daemon --mode module -p product=default -p buildMode=release assembleHap
  if ($LASTEXITCODE -ne 0) {
    throw 'Release build failed.'
  }

  $profile = Get-Content -Raw -Encoding UTF8 $appProfilePath | ConvertFrom-Json
  $actualVersionCode = [int]$profile.app.versionCode
  $signedHap = Get-ChildItem -Path (Join-Path $repoRoot 'entry\build\default\outputs\default') -Filter '*-signed.hap' -File |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($null -eq $signedHap) {
    throw 'The signed Release HAP was not found.'
  }
  New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
  $artifactName = "PalmVault-$VersionName-$actualVersionCode.hap"
  $artifactPath = Join-Path $releaseDirectory $artifactName
  Copy-Item -LiteralPath $signedHap.FullName -Destination $artifactPath -Force
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash.ToLowerInvariant()
  [System.IO.File]::WriteAllText("$artifactPath.sha256", "$hash  $artifactName`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "5/6 Artifact: $artifactPath"
  Write-Host "SHA-256: $hash"

  $hasOrigin = $false
  & git -C $repoRoot remote get-url origin *> $null
  if ($LASTEXITCODE -eq 0) { $hasOrigin = $true }
  if ($hasOrigin -and -not $NoPush) {
    Write-Host "6/6 Pushing $branch and $tagName..."
    Invoke-Git @('push', 'origin', "HEAD:refs/heads/$branch") | Out-Null
    Invoke-Git @('push', 'origin', $tagName) | Out-Null
  } elseif ($NoPush) {
    Write-Host '6/6 Push skipped by -NoPush.'
  } else {
    Write-Host '6/6 No origin remote; release remains local.'
  }
  Write-Host "Release $VersionName completed." -ForegroundColor Green
} catch {
  Write-Host "Release $VersionName failed: $($_.Exception.Message)" -ForegroundColor Red
  if ($tagged) {
    Write-Host "Commit and tag $tagName already exist; no automatic rollback was performed." -ForegroundColor Yellow
  } elseif ($committed) {
    Write-Host 'The release commit already exists; no automatic rollback was performed.' -ForegroundColor Yellow
  } elseif ($prepared) {
    Write-Host 'Prepared version changes remain for inspection.' -ForegroundColor Yellow
  }
  exit 1
}

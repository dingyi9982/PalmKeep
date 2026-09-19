param(
  [ValidateSet('Prepare', 'Tag')]
  [string]$Action = 'Prepare',
  [string]$VersionName = '',
  [int]$VersionCode = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appProfilePath = Join-Path $repoRoot 'AppScope\app.json5'
$rootPackagePath = Join-Path $repoRoot 'oh-package.json5'
$entryPackagePath = Join-Path $repoRoot 'entry\oh-package.json5'
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

function Invoke-Git {
  param([string[]]$Arguments)
  $output = & git -C $repoRoot @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Git command failed: git $($Arguments -join ' ')"
  }
  return $output
}

function Assert-CleanRepository {
  $status = @(Invoke-Git @('status', '--porcelain', '--untracked-files=all'))
  if ($status.Count -gt 0) {
    throw "The repository must be clean before preparing a release:`n$($status -join "`n")"
  }
}

function Read-AppProfile {
  return Get-Content -Raw -Encoding UTF8 $appProfilePath | ConvertFrom-Json
}

function ConvertTo-ReleaseVersion {
  param([string]$Value, [string]$Label)
  if ($Value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw "$Label '$Value' is invalid. Expected x.y.z, for example 1.0.1."
  }
  return [System.Version]::Parse($Value)
}

function Replace-JsonString {
  param([string]$Path, [string]$PropertyName, [string]$Value)
  $content = Get-Content -Raw -Encoding UTF8 $Path
  $pattern = '("' + [Regex]::Escape($PropertyName) + '"\s*:\s*")[^"]+("\s*[,$])'
  if (-not [Regex]::IsMatch($content, $pattern)) {
    throw "Unable to find $PropertyName in $Path"
  }
  $updated = [Regex]::Replace($content, $pattern, ('${1}' + $Value + '${2}'), 1)
  [System.IO.File]::WriteAllText($Path, $updated.Replace("`r`n", "`n"), $utf8WithoutBom)
}

if ($Action -eq 'Tag') {
  Assert-CleanRepository
  $profile = Read-AppProfile
  $tagName = "v$($profile.app.versionName)"
  & git -C $repoRoot rev-parse --quiet --verify "refs/tags/$tagName" *> $null
  if ($LASTEXITCODE -eq 0) {
    throw "Tag $tagName already exists."
  }
  Invoke-Git @('tag', '-a', $tagName, '-m', "Release $($profile.app.versionName)") | Out-Null
  Write-Host "Created $tagName."
  exit 0
}

$newVersion = ConvertTo-ReleaseVersion -Value $VersionName -Label 'VersionName'
$profile = Read-AppProfile
$currentVersionName = [string]$profile.app.versionName
$currentVersion = ConvertTo-ReleaseVersion -Value $currentVersionName -Label 'Current versionName'
if ($newVersion -le $currentVersion) {
  throw "The new versionName $VersionName must be greater than $currentVersionName."
}

$currentVersionCode = [int]$profile.app.versionCode
$nextVersionCode = if ($VersionCode -gt 0) { $VersionCode } else { $currentVersionCode + 1 }
if ($nextVersionCode -le $currentVersionCode) {
  throw "The new versionCode must be greater than $currentVersionCode."
}

Assert-CleanRepository
$appContent = Get-Content -Raw -Encoding UTF8 $appProfilePath
$appContent = [Regex]::Replace($appContent, '("versionCode"\s*:\s*)\d+', ('${1}' + $nextVersionCode), 1)
$appContent = [Regex]::Replace($appContent, '("versionName"\s*:\s*")[^"]+("\s*,)', ('${1}' + $VersionName + '${2}'), 1)
[System.IO.File]::WriteAllText($appProfilePath, $appContent.Replace("`r`n", "`n"), $utf8WithoutBom)
Replace-JsonString -Path $rootPackagePath -PropertyName 'version' -Value $VersionName
Replace-JsonString -Path $entryPackagePath -PropertyName 'version' -Value $VersionName
Write-Host "Prepared version $VersionName ($nextVersionCode)."

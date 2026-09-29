Set-StrictMode -Version Latest

function ConvertTo-PalmKeepReleaseVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value,
    [string]$Label = 'VersionName'
  )
  if ($Value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw "$Label '$Value' is invalid. Expected x.y.z without leading zeroes, for example 1.0.1."
  }
  try {
    return [System.Version]::Parse($Value)
  } catch {
    throw "$Label '$Value' is outside the supported numeric range."
  }
}

function Get-PalmKeepReleaseBaseline {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentVersionName,
    [string[]]$Tags = @()
  )
  $latest = ConvertTo-PalmKeepReleaseVersion -Value $CurrentVersionName -Label 'Current versionName'
  foreach ($tag in @($Tags)) {
    $match = [Regex]::Match([string]$tag, '^v((0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))$')
    if (-not $match.Success) { continue }
    $candidate = ConvertTo-PalmKeepReleaseVersion -Value $match.Groups[1].Value -Label "Release tag $tag"
    if ($candidate -gt $latest) { $latest = $candidate }
  }
  return $latest
}

function Assert-PalmKeepReleaseVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RequestedVersionName,
    [Parameter(Mandatory = $true)]
    [string]$CurrentVersionName,
    [Parameter(Mandatory = $true)]
    [int]$CurrentVersionCode,
    [string[]]$Tags = @(),
    [switch]$AllowInitialConfiguredVersion
  )
  $requested = ConvertTo-PalmKeepReleaseVersion -Value $RequestedVersionName -Label 'VersionName'
  $current = ConvertTo-PalmKeepReleaseVersion -Value $CurrentVersionName -Label 'Current versionName'
  $validTags = @($Tags | Where-Object {
    [string]$_ -match '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'
  })
  $baseline = Get-PalmKeepReleaseBaseline -CurrentVersionName $CurrentVersionName -Tags $Tags
  $isInitialConfiguredVersion = $AllowInitialConfiguredVersion -and $validTags.Count -eq 0 -and
    $CurrentVersionCode -eq 1 -and $requested -eq $current
  if (-not $isInitialConfiguredVersion -and $requested -le $baseline) {
    throw "VersionName '$RequestedVersionName' must be greater than latest version $baseline."
  }
  return $requested
}

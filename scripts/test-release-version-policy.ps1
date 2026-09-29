Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release-version-policy.ps1')

function Assert-Accepted {
  param(
    [string]$Requested,
    [string]$Current,
    [int]$CurrentCode,
    [string[]]$Tags = @(),
    [switch]$AllowInitial
  )
  [void](Assert-PalmKeepReleaseVersion -RequestedVersionName $Requested -CurrentVersionName $Current `
    -CurrentVersionCode $CurrentCode -Tags $Tags -AllowInitialConfiguredVersion:$AllowInitial)
}

function Assert-Rejected {
  param(
    [string]$Requested,
    [string]$Current,
    [int]$CurrentCode,
    [string[]]$Tags = @(),
    [string]$ExpectedMessage = 'must be greater'
  )
  try {
    [void](Assert-PalmKeepReleaseVersion -RequestedVersionName $Requested -CurrentVersionName $Current `
      -CurrentVersionCode $CurrentCode -Tags $Tags)
  } catch {
    if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
      throw "Unexpected rejection for ${Requested}: $($_.Exception.Message)"
    }
    return
  }
  throw "Expected version $Requested to be rejected."
}

Assert-Accepted -Requested '1.0.2' -Current '1.0.1' -CurrentCode 2 -Tags @('v1.0.0', 'v1.0.1')
Assert-Accepted -Requested '1.10.0' -Current '1.9.9' -CurrentCode 20 -Tags @('v1.9.9')
Assert-Accepted -Requested '1.0.0' -Current '1.0.0' -CurrentCode 1 -Tags @() -AllowInitial
Assert-Rejected -Requested '1.0.1' -Current '1.0.1' -CurrentCode 2 -Tags @('v1.0.0')
Assert-Rejected -Requested '1.0.0' -Current '1.0.1' -CurrentCode 2 -Tags @('v1.0.1')
Assert-Rejected -Requested '1.5.0' -Current '1.0.1' -CurrentCode 2 -Tags @('v2.0.0')
foreach ($invalid in @('1.0', '01.0.0', '1.0.0.0', '1.0.0-beta', 'v1.0.0')) {
  Assert-Rejected -Requested $invalid -Current '1.0.0' -CurrentCode 1 -Tags @() -ExpectedMessage 'is invalid'
}

Write-Host 'Release version policy tests passed.' -ForegroundColor Green

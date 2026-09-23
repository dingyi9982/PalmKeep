param(
  [switch]$All
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$textExtensions = @(
  '.ets', '.ts', '.js', '.mjs', '.ps1', '.cmd', '.json', '.json5', '.md', '.txt',
  '.xml', '.svg', '.css', '.html', '.c', '.h', '.cpp', '.hpp'
)
$textNames = @('.editorconfig', '.gitattributes', '.gitignore', 'LICENSE')
$skipPattern = '\\(\.git|\.hvigor|\.idea|\.cxx|build|entry\\build|oh_modules|node_modules|release)\\'

function Invoke-GitLines {
  param([string[]]$GitArgs)
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    return & git -C $repoRoot -c core.quotepath=false @GitArgs 2>$null
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Get-RepositoryFiles {
  if ($All) {
    return Get-ChildItem -Path $repoRoot -Recurse -File |
      Where-Object { $_.FullName -notmatch $skipPattern } |
      ForEach-Object { $_.FullName }
  }
  $tracked = Invoke-GitLines @('diff', '--name-only', '--diff-filter=ACMRT', 'HEAD')
  $untracked = Invoke-GitLines @('ls-files', '--others', '--exclude-standard')
  return @($tracked + $untracked) |
    Where-Object { $_ -and ($_ -notmatch '^\s*$') } |
    ForEach-Object { Join-Path $repoRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ }
}

$problems = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-RepositoryFiles) {
  $item = Get-Item -LiteralPath $file
  if (($textExtensions -notcontains $item.Extension.ToLowerInvariant()) -and
    ($textNames -notcontains $item.Name)) { continue }
  $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $problems.Add("$($item.FullName): has UTF-8 BOM")
  }
  try { $text = $utf8Strict.GetString($bytes) }
  catch {
    $problems.Add("$($item.FullName): is not valid UTF-8")
    continue
  }
  if ($text.Contains("`r`n")) { $problems.Add("$($item.FullName): contains CRLF line endings; use LF") }
  if ($text.Contains([char]0xFFFD)) { $problems.Add("$($item.FullName): contains Unicode replacement character U+FFFD") }
}

if ($problems.Count -gt 0) {
  $problems | ForEach-Object { Write-Error $_ -ErrorAction Continue }
  exit 1
}
Write-Host 'Text encoding check passed: UTF-8 without BOM, LF line endings.'

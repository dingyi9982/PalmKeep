param(
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\entry\src\debug\resources\rawfile\palmkeep_demo')
)

$ErrorActionPreference = 'Stop'
$sampleRate = 8000
$durationSeconds = 3
$amplitude = 5000

function Write-DemoWave {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][double]$Frequency
  )

  $sampleCount = $sampleRate * $durationSeconds
  $dataSize = $sampleCount * 2
  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
  $writer = [System.IO.BinaryWriter]::new($stream)
  try {
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([int](36 + $dataSize))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
    $writer.Write([int]16)
    $writer.Write([short]1)
    $writer.Write([short]1)
    $writer.Write([int]$sampleRate)
    $writer.Write([int]($sampleRate * 2))
    $writer.Write([short]2)
    $writer.Write([short]16)
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([int]$dataSize)
    for ($index = 0; $index -lt $sampleCount; $index += 1) {
      $fade = [Math]::Min(1.0, [Math]::Min($index / 1200.0, ($sampleCount - $index) / 1200.0))
      $sample = [short]($amplitude * $fade * [Math]::Sin(2.0 * [Math]::PI * $Frequency * $index / $sampleRate))
      $writer.Write($sample)
    }
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Write-DemoWave -Path (Join-Path $OutputDirectory 'meeting-opening.wav') -Frequency 440
Write-DemoWave -Path (Join-Path $OutputDirectory 'meeting-notes.wav') -Frequency 554.37
Write-DemoWave -Path (Join-Path $OutputDirectory 'meeting-summary.wav') -Frequency 659.25

Write-Host "Debug demo audio generated in $OutputDirectory"

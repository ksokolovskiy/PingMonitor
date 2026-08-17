param(
    [string]$Version = '0.0.0',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'outputs\ping-widget.ps1'
$outputDir = [IO.Path]::GetFullPath($OutputDirectory)
$outputExe = Join-Path $outputDir 'PingMonitor.exe'

if (-not (Test-Path $source)) {
    throw "Source file not found: $source"
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -Force

# PS2EXE file version metadata is safest as a four-part numeric version.
$parts = @($Version -split '\.')
while ($parts.Count -lt 4) { $parts += '0' }
$fileVersion = ($parts[0..3] -join '.')

Invoke-ps2exe `
    -InputFile $source `
    -OutputFile $outputExe `
    -NoConsole `
    -STA `
    -Title 'PingMonitor' `
    -Product 'PingMonitor' `
    -Company 'Kostya Sokolovskiy' `
    -Copyright 'Copyright (c) 2026 Kostya Sokolovskiy' `
    -Version $fileVersion

if (-not (Test-Path $outputExe)) {
    throw 'PingMonitor.exe was not created.'
}

$hash = (Get-FileHash -Algorithm SHA256 $outputExe).Hash
Write-Host "Built: $outputExe"
Write-Host "SHA256: $hash"

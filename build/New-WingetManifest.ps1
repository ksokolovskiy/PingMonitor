param(
    [Parameter(Mandatory)] [string]$Version,
    [Parameter(Mandatory)] [string]$InstallerUrl,
    [Parameter(Mandatory)] [string]$InstallerSha256,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist\winget')
)

$ErrorActionPreference = 'Stop'
$packageId = 'ksokolovskiy.PingMonitor'
$out = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $out | Out-Null

@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.12.0.schema.json
PackageIdentifier: $packageId
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.12.0
"@ | Set-Content -Encoding utf8 (Join-Path $out "$packageId.yaml")

@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.12.0.schema.json
PackageIdentifier: $packageId
PackageVersion: $Version
InstallerType: portable
Commands:
  - PingMonitor
Installers:
  - Architecture: x64
    InstallerUrl: $InstallerUrl
    InstallerSha256: $InstallerSha256
ManifestType: installer
ManifestVersion: 1.12.0
"@ | Set-Content -Encoding utf8 (Join-Path $out "$packageId.installer.yaml")

@"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json
PackageIdentifier: $packageId
PackageVersion: $Version
PackageLocale: en-US
Publisher: Kostya Sokolovskiy
PublisherUrl: https://github.com/ksokolovskiy
PublisherSupportUrl: https://github.com/ksokolovskiy/PingMonitor/issues
Author: Kostya Sokolovskiy
PackageName: PingMonitor
PackageUrl: https://github.com/ksokolovskiy/PingMonitor
License: MIT
LicenseUrl: https://github.com/ksokolovskiy/PingMonitor/blob/main/LICENSE
ShortDescription: Compact always-on-top ping monitoring widget for Windows.
Description: PingMonitor is a compact Windows ping status widget written in PowerShell/WinForms. It shows current latency and packet loss statistics for recent and long-term periods.
Moniker: pingmonitor
Tags:
  - ping
  - network
  - monitoring
  - latency
  - winforms
ManifestType: defaultLocale
ManifestVersion: 1.12.0
"@ | Set-Content -Encoding utf8 (Join-Path $out "$packageId.locale.en-US.yaml")

Write-Host "WinGet manifests written to $out"

# PingMonitor

Small Windows 11 ping status widget written in PowerShell/WinForms.

![PingMonitor widget screenshot](docs/screenshot.png)

It stays on top as a compact desktop widget and shows:

- target host
- online/degraded/offline status
- current latency
- packet loss for 1 minute, 1 hour, today, and all time
- detailed stats in tooltips

## Run

```powershell
pmw
```

Or directly:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\outputs\pmw.ps1 -Target 8.8.8.8 -IntervalSeconds 1 -TimeoutMs 1000
```

## Runtime Data

Persistent statistics are stored locally under:

```text
%LOCALAPPDATA%\PingMonitor
```

Runtime data and diagnostics are intentionally not committed to this repository.


## Install with WinGet

After the package is accepted into the WinGet community repository:

```powershell
winget install ksokolovskiy.PingMonitor
```

Release builds are produced automatically from version tags such as `v1.0.0`.
See [`winget/README.md`](winget/README.md) for publishing instructions.


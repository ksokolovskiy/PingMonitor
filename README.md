# PingMonitor

Small Windows 11 ping status widget written in PowerShell/WinForms.

![PingMonitor widget screenshot](docs/screenshot.png)

It stays on top as a compact desktop widget and shows:

- target host
- online/degraded/offline status
- current latency
- packet loss for 1 minute, 1 hour, today, and all time
- detailed stats in tooltips
- customizable window transparency (semi-transparent by default, solid opaque on mouse hover)

## Run

```powershell
pmw
```

Or directly:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\outputs\pmw.ps1 -Target 8.8.8.8 -IntervalSeconds 1 -TimeoutMs 1000 -IdleOpacity 0.35
```

## Transparency & Hover

- By default, the widget is semi-transparent (**65% transparent / 35% opacity**) while idle, and becomes **100% opaque** as soon as the mouse hovers over it so you can interact with it.
- **Configuring via UI**: Right-click anywhere on the widget and choose from the **Transparency** submenu (`85%`, `75%`, `65% (Default)`, `50%`, `30%`, or `0% Opaque`). The setting is immediately saved and persisted across runs.
- **Configuring via CLI**: Pass `-IdleOpacity` (or alias `-Opacity`), e.g. `-IdleOpacity 0.35` or `-Opacity 35`.

## Runtime Data & Settings

Persistent statistics and settings (`settings.json`) are stored locally under:

```text
%LOCALAPPDATA%\PingMonitor
```

Runtime data, settings, and diagnostics are intentionally not committed to this repository.

## Install with WinGet

After the package is accepted into the WinGet community repository:

```powershell
winget install ksokolovskiy.PingMonitor
```

Release builds are produced automatically from version tags such as `v1.0.0`.
See [`winget/README.md`](winget/README.md) for publishing instructions.

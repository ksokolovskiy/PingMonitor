# WinGet publishing

PingMonitor is built as a portable `PingMonitor.exe`. GitHub Actions creates a release whenever a tag matching `v*` is pushed.

## First release

```powershell
git tag v1.0.0
git push origin v1.0.0
```

The release workflow uploads:

- `PingMonitor.exe`
- `winget-manifests.zip`

The generated manifests target this package ID:

```text
ksokolovskiy.PingMonitor
```

After the GitHub Release exists, submit the manifests to `microsoft/winget-pkgs`.

Recommended route:

```powershell
winget install Microsoft.WingetCreate
wingetcreate new https://github.com/ksokolovskiy/PingMonitor/releases/download/v1.0.0/PingMonitor.exe
```

Use:

- Package identifier: `ksokolovskiy.PingMonitor`
- Installer type: `portable`
- Command: `PingMonitor`

After Microsoft accepts the package:

```powershell
winget install ksokolovskiy.PingMonitor
```

Upgrades:

```powershell
winget upgrade ksokolovskiy.PingMonitor
```

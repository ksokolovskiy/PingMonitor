@echo off
setlocal

set "PM_WIDGET=%~dp0pmw.ps1"
if not exist "%PM_WIDGET%" (
  echo [pmw] Widget script not found: %PM_WIDGET%
  exit /b 1
)

set "POWERSHELL=%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe"
start "" /B "%POWERSHELL%" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PM_WIDGET%" %*
exit /b 0

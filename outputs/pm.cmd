@echo off
setlocal

set "PM_SCRIPT=%~dp0pm.ps1"
if not exist "%PM_SCRIPT%" (
  echo [pm] Script not found: %PM_SCRIPT%
  exit /b 1
)

set "POWERSHELL=%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%PM_SCRIPT%" %*

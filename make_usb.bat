@echo off
rem ============================================================
rem  Pi Agent - USB builder launcher. ASCII only on purpose:
rem  every Chinese prompt lives in make_usb.ps1 (UTF-8 BOM).
rem  Double-click it, or run: make_usb.bat D: [-SkipRuntime] [-NoKey]
rem ============================================================
set "PS=powershell"
where powershell >nul 2>nul
if errorlevel 1 set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0make_usb.ps1" %*
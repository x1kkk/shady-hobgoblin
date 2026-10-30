@echo off
setlocal
rem ============================================================
rem  Pi Agent - USB fix tool launcher (ASCII only on purpose).
rem  Uses the FULL path to powershell.exe because this PC's PATH
rem  does not contain the WindowsPowerShell directory.
rem  Recommended: right-click -> "Run as administrator".
rem ============================================================
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix_usb.ps1" %*
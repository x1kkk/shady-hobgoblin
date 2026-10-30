@echo off
setlocal
rem Pi Agent - start the Chinese repair menu (ASCII only, full path to powershell)
set "PATH=%SystemRoot%\System32\WindowsPowerShell\v1.0;%SystemRoot%\System32;%PATH%"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\menu\pi_menu.ps1" -NoElevate
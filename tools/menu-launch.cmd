@echo off
setlocal
rem ============================================================
rem  Pi Agent ?????????
rem  ??????? Windows Terminal????????/????????
rem  ???menu-launch.cmd            ????
rem        menu-launch.cmd --check    ???????????
rem ============================================================
set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
rem ??????????????? `D:\\menu` ????????
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"
set "WT=%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe"

if /i "%~1"=="--check" (
  echo ROOT=%ROOT%
  echo PS=%PS%
  echo WT=%WT%
  echo MENU=%ROOT%\menu\pi_menu.ps1
  if exist "%ROOT%\menu\pi_menu.ps1" (echo MENU_EXISTS=1) else (echo MENU_EXISTS=0)
  endlocal
  exit /b 0
)

cd /d "%ROOT%"
chcp 65001 >nul 2>&1
rem ???????????????Pi ?????
set "PI_HARDWARE_CURSOR=1"

if exist "%WT%" (
  "%WT%" -w 0 new-tab --title "Pi Agent" "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\menu\pi_menu.ps1" -NoElevate
  endlocal
  exit /b 0
)
rem ? conhost ??????????WT ???????????????
mode con: cols=120 lines=40 >nul 2>&1
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\menu\pi_menu.ps1" -NoElevate
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
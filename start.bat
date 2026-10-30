@echo off
setlocal
rem ============================================================
rem  Pi Agent - entry point. ASCII only on purpose: all Chinese
rem  UI text lives in .ps1 files (UTF-8 BOM) so this launcher is
rem  safe under any console code page.
rem  Dispatch rules:
rem    no PowerShell  -> legacy menu (XP/2003; Chinese, GBK) or
rem                      "too old" notice for Windows 9x
rem    portable Pi    -> Pi menu (AI repair assistant)
rem    otherwise      -> PowerShell script menu (Win7/10/11)
rem ============================================================
set "ROOT=%~dp0"
set "PSFULL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PS=powershell"
if exist "%PSFULL%" set "PS=%PSFULL%"

if not exist "%PSFULL%" goto nops
if exist "%ROOT%runtime\pi\pi.cmd" if exist "%ROOT%runtime\pi\node.exe" if exist "%ROOT%runtime\pi\node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js" goto pimenu
goto psmenu

:pimenu
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%menu\pi_menu.ps1" -NoElevate
if errorlevel 1 "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%menu\msg.ps1" menufail
goto end

:psmenu
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%menu\main_menu.ps1" -NoElevate
if errorlevel 1 "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%menu\msg.ps1" menufail
goto end

:nops
rem No PowerShell: Windows XP/2003 or older
for /f "tokens=2 delims=[]" %%v in ('ver') do set "VERSTR=%%v"
set "VERSTR=%VERSTR:Version =%"
for /f "tokens=1 delims=." %%a in ("%VERSTR%") do set "OSMAJOR=%%a"
if "%OSMAJOR%"=="4" goto tooold
cmd /c ""%ROOT%core\legacy\legacy_menu.bat""
goto end

:tooold
echo.
echo [Pi Agent] This Windows version is too old (Windows 9x).
echo Pi Agent supports Windows XP/2003 and newer.
pause
goto end

:end
endlocal
@echo off
setlocal
rem ============================================================
rem  Pi Agent - portable Pi launcher (Windows 10/11 x64). ASCII only.
rem  Points Pi's config home at the USB stick and runs the bundled
rem  pi.cmd (which prefers the node.exe sitting next to it).
rem  Usage: start_pi.bat [pi arguments...]
rem ============================================================
chcp 65001 >nul
set "PATH=%SystemRoot%\System32\WindowsPowerShell\v1.0;%SystemRoot%\System32;%PATH%"
set "ROOT=%~dp0"
cd /d "%ROOT%"
set "PI_CODING_AGENT_DIR=%ROOT%pi-home\agent"
set "PI_CODING_AGENT_SESSION_DIR=%ROOT%pi-home\agent\sessions"
set "PI_TELEMETRY=0"
set "PI_SKIP_VERSION_CHECK=1"
set "TEMP=%ROOT%logs\tmp"
set "TMP=%ROOT%logs\tmp"
if not exist "%ROOT%logs\tmp" mkdir "%ROOT%logs\tmp"
set "PATH=%ROOT%runtime\pi;%PATH%"
"%ROOT%runtime\pi\pi.cmd" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
@echo off
setlocal
rem Project wrapper; paths are relative and no global Node/Pi fallback is used.
if not exist "%~dp0node.exe" (
  echo Portable Node missing. See docs\DEPENDENCIES.md.
  exit /b 2
)
if not exist "%~dp0node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js" (
  echo Portable Pi missing. See docs\DEPENDENCIES.md.
  exit /b 2
)
"%~dp0node.exe" "%~dp0node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

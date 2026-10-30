@echo off
chcp 936 >nul
setlocal
rem ============================================================
rem  Pi Agent - 老系统菜单（Windows XP / 2003）
rem ============================================================
set "ROOT=%~dp0..\..\"
title Pi Agent - 老系统菜单

:menu
cls
echo ================================================
echo   Pi Agent - 老系统菜单（Windows XP / 2003）
echo ================================================
echo   [1] 体检采集（约 2 分钟）
echo   [2] 查看最新报告
echo   [3] 尝试在线 AI 分析（XP 加密组件过旧可能失败）
echo   [4] 退出
echo.
echo   提示：XP 上建议先做 [1] 采集，再把 U 盘插到
echo   现代电脑上运行 analyze.bat 做 AI 分析。
echo ================================================
set "choice="
set /p choice=请选择： 
if "%choice%"=="1" goto collect
if "%choice%"=="2" goto view
if "%choice%"=="3" goto ai
if "%choice%"=="4" goto end
goto menu

:collect
call "%ROOT%core\legacy\collect.bat"
echo.
pause
goto menu

:view
set "LASTDIR="
for /f "delims=" %%d in ('dir /b /ad /o-d "%ROOT%reports" 2^>nul') do ( set "LASTDIR=%%d" & goto show )
:show
if defined LASTDIR (
  notepad "%ROOT%reports\%LASTDIR%\diagnosis.txt"
) else (
  echo 还没有报告，请先执行 [1] 采集。
)
pause
goto menu

:ai
set "LASTDIR="
for /f "delims=" %%d in ('dir /b /ad /o-d "%ROOT%reports" 2^>nul') do ( set "LASTDIR=%%d" & goto ask )
:ask
if defined LASTDIR (
  echo 正在请求 DeepSeek 分析，请稍候...
  cscript //nologo "%ROOT%ai\ask_deepseek.vbs" "%ROOT%reports\%LASTDIR%\diagnosis.txt" "%ROOT%reports\%LASTDIR%\ai_analysis.txt"
  echo.
  echo 结果已保存到报告目录的 ai_analysis.txt。
) else (
  echo 还没有报告，请先执行 [1] 采集。
)
pause
goto menu

:end
endlocal

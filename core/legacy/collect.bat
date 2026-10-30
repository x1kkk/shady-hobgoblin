@echo off
chcp 936 >nul
setlocal
rem ============================================================
rem  Pi Agent - 老系统采集器（Windows XP / 2003）
rem  输出：reports\<时间戳>_<计算机名>\diagnosis.txt（GBK 编码）
rem ============================================================
set "ROOT=%~dp0..\..\"

rem --- 时间戳通过 wmic 获取（失败则用 unknown） ---
set STAMP=unknown
if exist "%TEMP%\pistamp.tmp" del /q "%TEMP%\pistamp.tmp"
wmic os get localdatetime /value > "%TEMP%\pistamp.tmp" 2>nul
for /f "tokens=2 delims==" %%a in ('find "LocalDateTime" "%TEMP%\pistamp.tmp" 2^>nul') do set STAMP=%%a
if not "%STAMP%"=="unknown" set STAMP=%STAMP:~0,14%

set "DIRNAME=%STAMP%_%COMPUTERNAME%"
if not exist "%ROOT%reports" mkdir "%ROOT%reports"
set "OUTDIR=%ROOT%reports\%DIRNAME%"
mkdir "%OUTDIR%"
set "OUT=%OUTDIR%\diagnosis.txt"

echo 正在采集诊断信息，请稍候...

> "%OUT%" echo Pi Agent 诊断报告 v0.1（老系统采集器）
>> "%OUT%" echo 生成时间：%STAMP%
>> "%OUT%" echo 操作系统：%OS%
>> "%OUT%" echo SENSITIVE: %COMPUTERNAME%^|%USERNAME%
>> "%OUT%" echo.

>> "%OUT%" echo ===== 1. 系统信息 =====
systeminfo >> "%OUT%" 2>nul

>> "%OUT%" echo.
>> "%OUT%" echo ===== 2. 内存与进程 =====
wmic os get FreePhysicalMemory,TotalVisibleMemorySize /value >> "%OUT%" 2>nul
tasklist >> "%OUT%" 2>nul

>> "%OUT%" echo.
>> "%OUT%" echo ===== 3. 磁盘 =====
wmic logicaldisk get name,size,freespace /value >> "%OUT%" 2>nul
wmic diskdrive get model,size,status /value >> "%OUT%" 2>nul

>> "%OUT%" echo.
>> "%OUT%" echo ===== 4. 网络 =====
ipconfig /all >> "%OUT%" 2>nul
>> "%OUT%" echo --- ping 公网 IP ---
ping 223.5.5.5 -n 2 >> "%OUT%" 2>nul
>> "%OUT%" echo --- ping 域名（DNS 测试） ---
ping www.baidu.com -n 1 >> "%OUT%" 2>nul
>> "%OUT%" echo --- hosts 文件 ---
if exist "%SystemRoot%\system32\drivers\etc\hosts" type "%SystemRoot%\system32\drivers\etc\hosts" >> "%OUT%" 2>nul
>> "%OUT%" echo --- 防火墙配置 ---
netsh firewall show config >> "%OUT%" 2>nul

>> "%OUT%" echo.
>> "%OUT%" echo ===== 5. 正在运行的服务 =====
net start >> "%OUT%" 2>nul
>> "%OUT%" echo --- 自动启动但已停止的驱动 ---
wmic sysdriver where "State='Stopped' and StartMode='Auto'" get Name,DisplayName /value >> "%OUT%" 2>nul

>> "%OUT%" echo.
>> "%OUT%" echo ===== 6. 启动项 =====
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /s >> "%OUT%" 2>nul
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /s >> "%OUT%" 2>nul
>> "%OUT%" echo --- 启动文件夹 ---

>> "%OUT%" echo.
>> "%OUT%" echo ===== 7. 已安装的补丁 =====
wmic qfe get HotFixID,InstalledOn /value >> "%OUT%" 2>nul

>> "%OUT%" echo.
>> "%OUT%" echo ===== 8. 蓝屏转储 =====
if exist "%SystemRoot%\Minidump" dir "%SystemRoot%\Minidump" >> "%OUT%" 2>nul
if exist "%SystemRoot%\MEMORY.DMP" echo 存在 MEMORY.DMP >> "%OUT%"

>> "%OUT%" echo.
>> "%OUT%" echo ===== 9. 事件日志错误与安全 =====
cscript //nologo "%ROOT%core\legacy\collect.vbs" >> "%OUT%" 2>nul

echo.
echo 报告已保存到：
echo   %OUT%
endlocal

# ============================================================
# Pi Agent - 修复执行器 (fix.ps1)
# 兼容 Windows PowerShell 2.0+
# 用法: fix.ps1 -Root <U盘根> -Ids F01,F02 [-FindingIds R07] [-Yes] [-List]
# 所有操作前自动备份到 backups\<时间戳>\，全程记录 logs\actions.log
# ============================================================
param(
    [string]$Root = '',
    [string[]]$Ids = @(),
    [string[]]$FindingIds = @(),
    [switch]$List,
    [switch]$Yes
)
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Root) { $Root = (Get-Item (Join-Path $ScriptDir '..\..')).FullName }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log([string]$line) {
    $dir = Join-Path $Root 'logs'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Add-Content -Path (Join-Path $dir 'actions.log') -Value $line -Encoding UTF8
}

# --- 修复目录定义 ---
$Fixes = @(
    @{ id = 'F01'; title = '刷新 DNS 缓存'; risk = '低'; reboot = $false;
       desc = '执行 ipconfig /flushdns 与 /registerdns，解决域名解析异常。';
       run = { & ipconfig /flushdns | Out-Null; $c1 = $LASTEXITCODE; & ipconfig /registerdns | Out-Null; $c2 = $LASTEXITCODE; 'flushdns=' + $c1 + ' registerdns=' + $c2 } },
    @{ id = 'F02'; title = '重置网络协议栈 (Winsock/TCP-IP)'; risk = '中'; reboot = $true;
       desc = 'netsh winsock reset + int ip reset，修复网络协议栈损坏。完成后需重启。';
       run = { & netsh winsock reset | Out-Null; $c1 = $LASTEXITCODE; & netsh int ip reset | Out-Null; $c2 = $LASTEXITCODE; & ipconfig /flushdns | Out-Null; 'winsock=' + $c1 + ' ipreset=' + $c2 } },
    @{ id = 'F03'; title = '重置 WinHTTP 代理'; risk = '低'; reboot = $false;
       desc = 'netsh winhttp reset proxy，清除可能被恶意软件设置的代理。';
       run = { & netsh winhttp reset proxy | Out-Null; 'exit=' + $LASTEXITCODE } },
    @{ id = 'F04'; title = '重置 hosts 文件'; risk = '低'; reboot = $false;
       desc = '备份并重置 hosts 文件为默认内容。';
       run = { $h = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'; if (Test-Path $h) { Copy-Item $h (Join-Path $BackupDir 'hosts.bak') -Force }; $def = "# Pi Agent 重置`r`n127.0.0.1 localhost`r`n::1 localhost`r`n"; Set-Content -Path $h -Value $def -Encoding ASCII; 'hosts 已重置，原文件备份于 backups\' + (Split-Path $BackupDir -Leaf) + '\hosts.bak' } },
    @{ id = 'F05'; title = 'SFC 系统文件修复'; risk = '中'; reboot = $false;
       desc = 'sfc /scannow 修复损坏的系统文件（约 5~15 分钟）。';
       run = { $out = (& sfc /scannow) -join "`r`n"; $c = $LASTEXITCODE; (($out -split "`r`n" | Select-Object -Last 5) -join "`r`n") + "`r`nexit=" + $c } },
    @{ id = 'F06'; title = 'DISM 组件存储修复'; risk = '中'; reboot = $false;
       desc = 'dism /online /cleanup-image /restorehealth 修复组件存储（约 10~30 分钟，需联网）。';
       run = { $out = (& dism /online /cleanup-image /restorehealth) -join "`r`n"; $c = $LASTEXITCODE; (($out -split "`r`n" | Select-Object -Last 5) -join "`r`n") + "`r`nDISM exit=" + $c } },
    @{ id = 'F07'; title = '清除可疑启动项'; risk = '中'; reboot = $false;
       desc = '备份注册表键后删除被标记为可疑的 Run 启动项（由体检规则标记）。';
       run = { 'F07 按体检标记逐项处理' } },
    @{ id = 'F08'; title = '重置 Windows 更新缓存'; risk = '中'; reboot = $true;
       desc = '停止更新服务，重命名 SoftwareDistribution，重启服务。完成后需重启。';
       run = { (& net stop wuauserv) | Out-Null; (& net stop bits) | Out-Null; (& net stop cryptsvc) | Out-Null; $ts = Get-Date -Format 'yyyyMMddHHmmss'; $sd = Join-Path $env:WINDIR 'SoftwareDistribution'; $r1 = ''; if (Test-Path $sd) { Rename-Item $sd ('SoftwareDistribution.bak.' + $ts); $r1 = 'SoftwareDistribution 已重命名备份' } else { $r1 = '未发现 SoftwareDistribution' }; (& net start wuauserv) | Out-Null; (& net start bits) | Out-Null; (& net start cryptsvc) | Out-Null; $r1 } },
    @{ id = 'F09'; title = '清理临时文件'; risk = '低'; reboot = $false; del = $true;
       desc = '清理当前用户与系统临时目录（占用中的文件会跳过）。';
       run = { $paths = @($env:TEMP, (Join-Path $env:WINDIR 'Temp')); $freed = 0; foreach ($p in $paths) { if (Test-Path $p) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $sz = 0; if ($_.PSIsContainer) { $sz = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { $sz = $_.Length }; Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop; $freed += $sz } catch { } } } }; '已清理约 ' + [math]::Round($freed / 1MB, 1) + ' MB（部分占用文件已跳过）' } },
    @{ id = 'F10'; title = 'chkdsk 磁盘检查与修复'; risk = '中'; reboot = $true;
       desc = '对当前系统盘执行 chkdsk /f，系统盘将在下次重启时执行。';
       run = { $o = (cmd /c ('echo y| chkdsk ' + $env:SystemDrive + ' /f')) -join "`r`n"; (($o -split "`r`n" | Select-Object -Last 6) -join "`r`n") } },
    @{ id = 'F11'; title = '重建引导记录 (BCD)'; risk = '高'; reboot = $true;
       desc = 'bootrec /fixmbr /fixboot /rebuildbcd（Win7+）。完成后需重启。';
       run = { $r1 = ''; & bootrec /fixmbr | Out-Null; $r1 += 'fixmbr=' + $LASTEXITCODE + ' '; & bootrec /fixboot | Out-Null; $r1 += 'fixboot=' + $LASTEXITCODE + ' '; & bootrec /rebuildbcd | Out-Null; $r1 += 'rebuildbcd=' + $LASTEXITCODE; $r1 } },
    @{ id = 'F12'; title = '启用 Defender 实时保护'; risk = '低'; reboot = $false;
       desc = '启动 WinDefend 服务并清除禁用策略（Win8+）。';
       run = { $r1 = ''; try { Start-Service WinDefend -ErrorAction Stop; $r1 += 'WinDefend 已启动 ' } catch { $r1 += '服务启动失败: ' + $_.Exception.Message + ' ' }; New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Force | Out-Null; Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name DisableAntiSpyware -Value 0 -ErrorAction SilentlyContinue; Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name DisableRealtimeMonitoring -Value 0 -ErrorAction SilentlyContinue; $r1 + '禁用策略已清除' } },
    @{ id = 'F13'; title = '重置并开启 Windows 防火墙'; risk = '中'; reboot = $false;
       desc = 'netsh advfirewall reset 并开启所有配置文件（Win7+）。';
       run = { & netsh advfirewall reset | Out-Null; $c1 = $LASTEXITCODE; & netsh advfirewall set allprofiles state on | Out-Null; $c2 = $LASTEXITCODE; 'reset=' + $c1 + ' seton=' + $c2 } }
    @{ id = 'F14'; title = '重启打印服务并清空打印队列'; risk = '中'; reboot = $false; del = $true;
       desc = '停止 Spooler，把队列文件备份到 backups\ 后清空（未完成的打印任务会丢失），再启动服务。';
       run = { $bak = Join-Path $BackupDir 'spool_PRINTERS'; New-Item -ItemType Directory -Force -Path $bak | Out-Null; (& net stop spooler) | Out-Null; Start-Sleep -Seconds 2; $sp = Join-Path $env:WINDIR 'System32\spool\PRINTERS'; $n = 0; if (Test-Path $sp) { Get-ChildItem $sp -File -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $bak -Force -ErrorAction SilentlyContinue; Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; $n++ } }; (& net start spooler) | Out-Null; Start-Sleep -Seconds 1; $st = (Get-Service Spooler).Status; '已备份并清空 ' + $n + ' 个队列文件；Spooler 状态: ' + $st } },
    @{ id = 'F15'; title = '恢复自动获取 IP 与 DNS 并续租'; risk = '中'; reboot = $false;
       desc = '把已启用网卡改为 DHCP 自动获取并释放/续租。重要：如果这台机器原本是固定 IP（实验室常见），执行后会丢失原配置！请先确认。';
       run = { $r = @(); $cfgs = @(Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }); foreach ($c in $cfgs) { $na = Get-WmiObject Win32_NetworkAdapter -Filter ('Index=' + $c.Index); $nm = $na.NetConnectionID; if ($nm) { (& netsh interface ip set address name="$nm" source=dhcp) | Out-Null; (& netsh interface ip set dns name="$nm" source=dhcp) | Out-Null; $r += ($nm + ' 已设为自动获取') } }; (& ipconfig /release) | Out-Null; (& ipconfig /renew) | Out-Null; $ip = @(Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled } | Select-Object -First 1).IPAddress; ($r -join '；') + '；当前IP: ' + ($ip -join ', ') } },
    @{ id = 'F16'; title = '清理系统/IE/环境变量代理'; risk = '中'; reboot = $false; del = $true;
       desc = '备份后关闭 IE 代理、重置 WinHTTP 代理、清除用户级 http_proxy 等代理环境变量（加速器/旧代理残留常见）。如学校要求使用明文代理，请勿执行。';
       run = { $bakFile = Join-Path $BackupDir 'proxy_original.txt'; $L = @(); $wh = (& netsh winhttp show proxy) -join ' '; $L += ('WinHTTP: ' + $wh); $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue; if ($ie) { $L += ('IE ProxyEnable=' + $ie.ProxyEnable + ' ProxyServer=' + $ie.ProxyServer); Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0 -ErrorAction SilentlyContinue; Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer -ErrorAction SilentlyContinue }; foreach ($n in @('http_proxy','HTTP_PROXY','https_proxy','HTTPS_PROXY','no_proxy','NO_PROXY')) { $v = [Environment]::GetEnvironmentVariable($n,'User'); if ($v) { $L += ($n + '=' + $v); [Environment]::SetEnvironmentVariable($n,$null,'User'); Set-Item -Path ('env:' + $n) -Value $null -ErrorAction SilentlyContinue } }; $L | Out-File -FilePath $bakFile -Encoding UTF8; (& netsh winhttp reset proxy) | Out-Null; 'WinHTTP/IE 代理已清理，用户级代理环境变量已清除；原值已备份到 ' + $bakFile } },
    @{ id = 'F17'; title = '重新启用被禁用的网卡'; risk = '中'; reboot = $false;
       desc = '把"已禁用"状态的物理网卡重新启用（不改动 IP 配置）。';
       run = { $n = 0; $r = @(); try { $bad = @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Disabled' }); foreach ($a in $bad) { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop; $r += $a.Name; $n++ } } catch { }; if ($n -eq 0) { $bad2 = @(Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -and $_.NetEnabled -eq $false -and $_.NetConnectionID }); foreach ($b in $bad2) { $b.Enable() | Out-Null; $r += $b.NetConnectionID; $n++ } }; '已尝试启用 ' + $n + ' 个网卡: ' + ($r -join ', ') } },
    @{ id = 'F18'; title = '共享打印兼容修复（0x0000011b）'; risk = '中'; reboot = $false;
       desc = '设置 HKLM\SYSTEM\CurrentControlSet\Control\Print\RpcAuthnLevelPrivacyEnabled=0 并重启打印服务。属安全权衡（削弱 RPC 打印补丁），仅在校方允许时用于修复共享打印报 0x0000011b。';
       run = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; $old = (Get-ItemProperty -Path $k -Name RpcAuthnLevelPrivacyEnabled -ErrorAction SilentlyContinue).RpcAuthnLevelPrivacyEnabled; ('原值: ' + $old) | Out-File -FilePath (Join-Path $BackupDir 'print_rpc_original.txt') -Encoding UTF8; Set-ItemProperty -Path $k -Name RpcAuthnLevelPrivacyEnabled -Value 0 -Type DWord; (& net stop spooler) | Out-Null; (& net start spooler) | Out-Null; '已设置 RpcAuthnLevelPrivacyEnabled=0（原值 ' + $old + '）并重启打印服务；若客户端报错消失即修复生效' } },
    @{ id = 'F19'; title = '创建标准 RAW 9100 打印端口'; risk = '低'; reboot = $false;
       desc = '为指定 IP 创建标准 RAW 9100 端口（用于替换不稳定的 WSD 端口）。执行时需输入打印机 IP。';
       run = { $ip = Read-Host '请输入打印机 IP（如 10.1.2.30），直接回车取消'; if (-not $ip) { '已取消（未输入 IP）' } else { $ip = $ip.Trim(); $pname = 'IP_' + $ip; $has = $false; try { $has = [bool](@(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object { $_.PrinterHostAddress -eq $ip -and $_.PortNumber -eq 9100 }).Count -gt 0) } catch { }; if ($has) { '已存在指向 ' + $ip + ' 的 9100 端口，请在打印机属性→端口中改选' } else { try { Add-PrinterPort -Name $pname -PrinterHostAddress $ip -PortNumber 9100 -ErrorAction Stop; '已创建端口 ' + $pname + '，请在打印机属性→端口中改选它' } catch { '自动创建失败（' + $_.Exception.Message + '）。请手动操作：控制面板→设备和打印机→添加打印机→添加本地打印机→创建新端口→Standard TCP/IP Port→输入 ' + $ip + '→设备类型选"自定义/TCP 9100"' } } } } },
    @{ id = 'F20'; title = '上网故障急救（组合动作）'; risk = '中'; reboot = $false;
       desc = '按固定顺序：启用被禁用网卡 → 刷新 DNS → 清理代理 → 若为 DHCP 则续租 → 验证网关/外网/域名三段连通。不会改动固定 IP 配置。';
       run = { $r = @(); $n = 0; try { foreach ($a in @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Disabled' })) { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop; $n++ } } catch { }; $r += ('启用网卡 ' + $n + ' 个'); (& ipconfig /flushdns) | Out-Null; $r += 'DNS缓存已刷新'; (& netsh winhttp reset proxy) | Out-Null; Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0 -ErrorAction SilentlyContinue; $r += '代理已关闭'; $dhcp = @(Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DHCPEnabled }); if ($dhcp.Count -gt 0) { (& ipconfig /release) | Out-Null; (& ipconfig /renew) | Out-Null; $r += 'DHCP 已续租' } else { $r += '非DHCP环境，跳过续租（保护固定IP）' }; $gw = @(@(Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled } | ForEach-Object { $_.DefaultIPGateway }) | Where-Object { $_ }); if ($gw.Count -gt 0) { $pg = Test-Connection -ComputerName $gw[0] -Count 2 -ErrorAction SilentlyContinue; $r += ('网关 ' + $gw[0] + ' 连通: ' + $(if ($pg) { '是' } else { '否' })) }; $pn = Test-Connection -ComputerName '223.5.5.5' -Count 2 -ErrorAction SilentlyContinue; $r += ('外网IP连通: ' + $(if ($pn) { '是' } else { '否' })); $pd = Test-Connection -ComputerName 'www.baidu.com' -Count 1 -ErrorAction SilentlyContinue; $r += ('域名解析: ' + $(if ($pd) { '正常' } else { '失败' })); ($r -join '；') } },
    @{ id = 'F21'; title = '重启校园网认证客户端服务'; risk = '中'; reboot = $false;
       desc = '查找并重启锐捷/深澜/iNode/Dr.COM 等认证相关服务（只重启，不卸载重装）。';
       run = { $pat = 'ruijie|supplicant|srun|inode|drcom|8021x|h3c|锐捷|深澜|认证'; $svcs = @(Get-Service | Where-Object { $_.Name -match $pat -or $_.DisplayName -match $pat }); if ($svcs.Count -eq 0) { '未发现校园网认证相关服务（可能未安装认证客户端，请到校园网自助页面下载安装）' } else { $r = @(); foreach ($s in $svcs) { try { Restart-Service -Name $s.Name -Force -ErrorAction Stop; $r += ($s.Name + ' 已重启') } catch { $r += ($s.Name + ' 重启失败: ' + $_.Exception.Message) } }; ($r -join '；') }} }
)

if ($List) {
    Write-Host ''
    Write-Host '可用的修复动作:'
    Write-Host ('{0}  {1,-26} {2,-4} {3,-6} {4}' -f 'ID', '名称', '风险', '重启', '说明')
    foreach ($f in $Fixes) {
        Write-Host ('{0}  {1,-26} {2,-4} {3,-6} {4}' -f $f.id, $f.title, $f.risk, $(if ($f.reboot) { '需要' } else { '否' }), $f.desc)
    }
    exit 0
}

if (-not (Test-Admin)) {
    Write-Host '修复操作需要管理员权限。请以管理员身份重新运行菜单。'
    exit 2
}

if ($Ids.Count -eq 0 -and $FindingIds.Count -eq 0) {
    Write-Host '未指定要执行的修复。用法: fix.ps1 -Ids F01,F02'
    Write-Host '可用 ID: F01~F13（用 -List 查看明细）'
    exit 1
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir = Join-Path $Root ('backups\' + $stamp)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ('备份目录: ' + $BackupDir)
Write-Log ('==== ' + $stamp + ' 修复会话开始 ====')

$needsReboot = $false

# --- 读取体检标记（用于 F07 逐项处理） ---
$findingsLines = @()
if ($FindingIds.Count -gt 0) {
    $latestDir = Get-ChildItem (Join-Path $Root 'reports') | Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestDir) {
        $ff = Join-Path $latestDir.FullName 'findings.ini'
        if (Test-Path $ff) { $findingsLines = @(Get-Content $ff -Encoding UTF8) }
    }
}

# --- 逐项执行 ---
foreach ($id in $Ids) {
    $fix = $Fixes | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $fix) { Write-Host ('未知修复编号: ' + $id + '（已跳过）'); continue }
    Write-Host ''
    $delTag = ''; if ($fix.PSObject.Properties.Name -contains 'del' -and $fix.del) { $delTag = '  [删除类]' }
    Write-Host ('[' + $fix.id + '] ' + $fix.title + '  (风险: ' + $fix.risk + ', 需重启: ' + $(if ($fix.reboot) { '是' } else { '否' }) + ')' + $delTag) -ForegroundColor $(if ($delTag) { 'Yellow' } else { 'Gray' })
    Write-Host ('  说明: ' + $fix.desc)
    $isDel = $false
    if ($fix.PSObject.Properties.Name -contains 'del') { $isDel = [bool]$fix.del }
    $ok = $Yes
    if ($isDel) {
        Write-Host ''
        Write-Host '  *** 本动作包含【删除】操作（不可撤销）***' -ForegroundColor Yellow
        if ($Yes) {
            Write-Host '  （-Yes 授权：上层门禁已由人工确认，本动作为删除类）' -ForegroundColor DarkYellow
            Write-Log ($stamp + '|' + $fix.id + '|删除类动作(-Yes授权)|' + $fix.title)
            $ok = $true
        } else {
            $a = ''
            try { $a = Read-Host '  输入 DELETE 表示确认执行（其他任意输入取消）' } catch { $a = '' }
            if ([string]::IsNullOrWhiteSpace($a)) {
                Write-Host '  [拒绝] 非交互环境无法人工确认删除，本动作已跳过。' -ForegroundColor Yellow
                Write-Log ($stamp + '|' + $fix.id + '|已跳过(非交互无确认)|' + $fix.title)
                continue
            }
            $ok = ($a -eq 'DELETE' -or $a -eq 'delete')
        }
    } elseif (-not $Yes) {
        $a = Read-Host '  是否执行? (y/n)'
        $ok = ($a -eq 'y' -or $a -eq 'Y')
    }
    if (-not $ok) {
        Write-Log ($stamp + '|' + $fix.id + '|已跳过(用户取消)|')
        Write-Host '  已跳过。'
        continue
    }
    Write-Log ($stamp + '|' + $fix.id + '|开始|' + $fix.title)
    Write-Host '  执行中...'
    $result = ''
    try { $result = & $fix.run } catch { $result = '异常: ' + $_.Exception.Message }
    Write-Host ('  结果: ' + $result)
    Write-Log ($stamp + '|' + $fix.id + '|结束|' + $result)
    if ($fix.reboot) { $needsReboot = $true }
}

# --- F07 可疑启动项逐项处理 ---
$f07Lines = @()
foreach ($line in $findingsLines) {
    $parts = $line -split '\|', 5
    if ($parts.Count -ge 5 -and $parts[2] -eq 'F07') {
        if ($FindingIds -contains $parts[0]) { $f07Lines += $line }
    }
}
if ($Ids -contains 'F07' -and $FindingIds.Count -eq 0) {
    $f07Lines = @()
    foreach ($line in $findingsLines) {
        $parts = $line -split '\|', 5
        if ($parts.Count -ge 5 -and $parts[2] -eq 'F07') { $f07Lines += $line }
    }
}
foreach ($line in $f07Lines) {
    $parts = $line -split '\|', 5
    $detail = $parts[4]
    $m = [regex]::Match($detail, 'KEY=([^;]+);VAL=(.+)')
    if (-not $m.Success) { continue }
    $psKey = $m.Groups[1].Value
    $valName = $m.Groups[2].Value
    $regKey = $psKey -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\'
    Write-Host ''
    Write-Host ('[F07] 清除可疑启动项: ' + $valName + ' @ ' + $psKey)

    Write-Host '  *** 本操作将【删除】该注册表启动项值（删除类动作，不可撤销）***' -ForegroundColor Yellow
    $ok = $Yes
    if ($Yes) {
        Write-Host '  （-Yes 授权：上层门禁已由人工确认）' -ForegroundColor DarkYellow
        Write-Log ($stamp + '|F07|删除类动作(-Yes授权)|' + $valName)
    } else {
        $a = ''
        try { $a = Read-Host '  输入 DELETE 表示确认删除（其他任意输入取消）' } catch { $a = '' }
        if ([string]::IsNullOrWhiteSpace($a)) {
            Write-Host '  [拒绝] 非交互环境无法人工确认删除，已跳过。' -ForegroundColor Yellow
            Write-Log ($stamp + '|F07|已跳过(非交互无确认)|' + $valName)
            continue
        }
        $ok = ($a -eq 'DELETE' -or $a -eq 'delete')
    }
    if (-not $ok) { Write-Log ($stamp + '|F07|已跳过(用户取消)|' + $valName); continue }
    $bak = Join-Path $BackupDir ('runkey_' + $valName + '.reg')
    & reg export $regKey $bak /y | Out-Null
    Write-Log ($stamp + '|F07|开始|' + $valName + ' (备份 ' + $bak + ')')
    $r = Remove-ItemProperty -Path $psKey -Name $valName -ErrorAction SilentlyContinue
    if ($?) { $result = '已删除 ' + $valName } else { $result = '删除失败（可能已被清理或权限不足）' }
    Write-Host ('  结果: ' + $result)
    Write-Log ($stamp + '|F07|结束|' + $result)
}

Write-Log ('==== ' + $stamp + ' 修复会话结束 ====')
Write-Host ''
if ($needsReboot) {
    Write-Host '部分修复需要重启电脑才能完全生效，请尽快重启。'
} else {
    Write-Host '本次修复无需重启。'
}
Write-Host ('操作日志: ' + (Join-Path $Root 'logs\actions.log'))
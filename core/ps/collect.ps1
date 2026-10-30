# ============================================================
# Pi Agent - 诊断采集器 (collect.ps1)
# 兼容 Windows PowerShell 2.0+ (Win7/2008 及以上)
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 -Root <U盘根> [-Fast]
# 产出: reports\<时间戳>_<计算机名>\diagnosis.txt / findings.ini / diagnosis.html
# ============================================================
param(
    [string]$Root = '',
    [string]$OutDir = '',
    [switch]$Fast,
    [switch]$NoProgress
)

$ErrorActionPreference = 'SilentlyContinue'

# --- 路径与基础信息 ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Root) { $Root = (Get-Item (Join-Path $ScriptDir '..\..')).FullName }
$ReportsRoot = Join-Path $Root 'reports'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$IsAdmin = Test-Admin

$ComputerName = $env:COMPUTERNAME
$UserName = $env:USERNAME
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not $OutDir) {
    $OutDir = Join-Path $ReportsRoot ($Stamp + '_' + $ComputerName)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ReportFile = Join-Path $OutDir 'diagnosis.txt'
$FindingsFile = Join-Path $OutDir 'findings.ini'
$HtmlFile = Join-Path $OutDir 'diagnosis.html'

# --- 报告缓冲与查找结果容器 ---
$sb = New-Object System.Text.StringBuilder
$script:Findings = @()

function Add-Line([string]$t) { [void]$script:sb.AppendLine($t) }
function Add-Section([string]$title) { Add-Line ''; Add-Line ('===== ' + $title + ' =====') }
function Add-Finding([string]$id, [string]$sev, [string]$fix, [string]$title, [string]$detail) {
    $script:Findings += ,@($id, $sev, $fix, $title, $detail)
}
function Info([string]$t) {
    if (-not $NoProgress) { Write-Host ('  [..] ' + $t) }
}

# 以固定代码页(936)运行控制台命令并正确解码输出，避免中文乱码
function Get-ConsoleText([string]$cmd) {
    $tmp = Join-Path $env:TEMP ('pia_' + [guid]::NewGuid().ToString('N') + '.txt')
    & cmd /c ('chcp 936 >nul & ' + $cmd + ' > "' + $tmp + '" 2>&1') | Out-Null
    $txt = ''
    if (Test-Path $tmp) {
        $bytes = [IO.File]::ReadAllBytes($tmp)
        $txt = [Text.Encoding]::GetEncoding(936).GetString($bytes)
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    return $txt
}

# --- 头部 ---
Add-Line 'Pi Agent 诊断报告 v0.2'
Add-Line ('生成时间 : ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
Add-Line ('操作系统 : ' + $env:OS)
Add-Line ('管理员权限: ' + $(if ($IsAdmin) { '是' } else { '否（部分检查与全部修复不可用）' }))
Add-Line ('模式      : ' + $(if ($Fast) { '快速体检' } else { '完整体检' }))
Add-Line ('SENSITIVE: ' + $ComputerName + '|' + $UserName)

# ========== 1. 系统信息 ==========
Info '采集系统信息'
Add-Section '1. 系统信息'
$os = Get-WmiObject Win32_OperatingSystem
$cs = Get-WmiObject Win32_ComputerSystem
$cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
$bios = Get-WmiObject Win32_BIOS
if ($os) {
    Add-Line ('系统版本 : ' + $os.Caption + ' ' + $os.Version + ' Build ' + $os.BuildNumber + ' ' + $os.CSDVersion)
    Add-Line ('系统架构 : ' + $os.OSArchitecture + ' / 进程 ' + $env:PROCESSOR_ARCHITECTURE)
    if ($os.InstallDate) { Add-Line ('安装日期 : ' + $os.ConvertToDateTime($os.InstallDate).ToString('yyyy-MM-dd')) }
    if ($os.LastBootUpTime) {
        $boot = $os.ConvertToDateTime($os.LastBootUpTime)
        $up = (Get-Date) - $boot
        Add-Line ('上次启动 : ' + $boot.ToString('yyyy-MM-dd HH:mm:ss') + ' (已运行 ' + [int]$up.TotalHours + ' 小时 ' + $up.Minutes + ' 分)')
    }
} else {
    Add-Line 'WMI 查询失败：系统信息不可用（WMI 服务异常本身可能就是故障信号）'
}
if ($cs) { Add-Line ('机型      : ' + $cs.Manufacturer + ' ' + $cs.Model + ' / 物理内存 ' + [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) + ' GB') }
if ($cpu) { Add-Line ('处理器   : ' + $cpu.Name + ' / ' + $cpu.NumberOfCores + ' 核') }
if ($bios) { Add-Line ('BIOS      : ' + $bios.SMBIOSBIOSVersion + ' / ' + $bios.Manufacturer) }

# ========== 2. 内存与进程 ==========
Info '采集内存与进程'
Add-Section '2. 内存与进程'
if ($os) {
    $totMB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
    $freeMB = [math]::Round($os.FreePhysicalMemory / 1KB)
    Add-Line ('物理内存 : 共 ' + $totMB + ' MB，可用 ' + $freeMB + ' MB')
    if ($freeMB -lt 500) { Add-Finding 'R13' '高' '' '内存不足（可用 < 500MB）' ('当前可用内存仅 ' + $freeMB + ' MB，建议关闭高占用程序或增加内存') }
} else {
    Add-Line '物理内存 : WMI 不可用'
}
$cpuLoad = (Get-WmiObject Win32_Processor | Select-Object -First 1).LoadPercentage
if ($null -ne $cpuLoad) {
    Add-Line ('CPU 负载 : ' + $cpuLoad + '%（瞬时值）')
} else {
    Add-Line 'CPU 负载 : 不可用(WMI)'
}
Add-Line '占用内存前 10 的进程:'
$procs = @(Get-Process | Sort-Object WS -Descending | Select-Object -First 10)
foreach ($p in $procs) {
    Add-Line ('  - ' + $p.ProcessName + ' : ' + [math]::Round($p.WS / 1MB) + ' MB (PID ' + $p.Id + ')')
}

# ========== 3. 磁盘 ==========
Info '采集磁盘信息'
Add-Section '3. 磁盘与空间'
$drives = @(Get-WmiObject Win32_LogicalDisk -Filter 'DriveType=3')
if ($drives.Count -eq 0) {
    Add-Line 'WMI 磁盘查询失败，改用 PowerShell 驱动器信息:'
    $psd = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)
    foreach ($d in $psd) {
        if ($null -ne $d.Used) {
            $sizeGB = [math]::Round($d.Used / 1GB + $d.Free / 1GB, 1)
            if ($sizeGB -le 0) {
                Add-Line ($d.Name + '  大小未知（受限环境）')
                continue
            }
            $freeGB = [math]::Round($d.Free / 1GB, 1)
            $pct = 0
            if ($sizeGB -gt 0) { $pct = [math]::Round(100 * $freeGB / $sizeGB, 0) }
            Add-Line ($d.Name + '  共 ' + $sizeGB + ' GB，剩余 ' + $freeGB + ' GB (' + $pct + '%)')
            if ($pct -lt 10) { Add-Finding 'R08' '中' 'F09' ('磁盘 ' + $d.Name + ' 空间不足') ('剩余空间仅 ' + $pct + '%，建议清理临时文件') }
        }
    }
} else {
    foreach ($d in $drives) {
        $sizeGB = [math]::Round($d.Size / 1GB, 1)
        $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
        if ($d.Size -gt 0) { $pct = [math]::Round(100 * $d.FreeSpace / $d.Size, 0) } else { $pct = 0 }
        Add-Line ($d.DeviceID + '  共 ' + $sizeGB + ' GB，剩余 ' + $freeGB + ' GB (' + $pct + '%)')
        if ($pct -lt 10) { Add-Finding 'R08' '中' 'F09' ('磁盘 ' + $d.DeviceID + ' 空间不足') ('剩余空间仅 ' + $pct + '%，建议清理临时文件') }
    }
}
$disks = @(Get-WmiObject Win32_DiskDrive)
if ($disks.Count -eq 0) {
    Add-Line '物理盘  : WMI 不可用'
} else {
    foreach ($dk in $disks) {
        Add-Line ('物理盘  : ' + $dk.Model + '  ' + [math]::Round($dk.Size / 1GB, 0) + ' GB ' + $dk.InterfaceType)
    }
}
$smart = Get-WmiObject -Namespace 'root\wmi' -Class MSStorageDriver_FailurePredictStatus
if ($smart) {
    foreach ($s in $smart) {
        $bad = $(if ($s.PredictFailure) { '是(磁盘报告故障风险!)' } else { '否' })
        Add-Line ('SMART    : ' + $s.InstanceName + ' 预测故障: ' + $bad)
        if ($s.PredictFailure) { Add-Finding 'R15' '高' '' '磁盘 SMART 预测故障' ('磁盘 ' + $s.InstanceName + ' 报告存在故障风险，请尽快备份数据') }
    }
} else { Add-Line 'SMART    : 无法获取（WMI 不支持）' }

# ========== 4. 事件日志 ==========
Info '采集事件日志'
$hours = 48
if (-not $Fast) { $hours = 168 }
Add-Section ('4. 事件日志错误摘要 (最近 ' + $hours + ' 小时)')
foreach ($logName in @('System', 'Application')) {
    $since = (Get-Date).AddHours(-$hours)
    $evts = @()
    try {
        $evts = @(Get-WinEvent -FilterHashtable @{LogName = $logName; StartTime = $since; Level = 1} -MaxEvents 800 -ErrorAction Stop)
        $evts += @(Get-WinEvent -FilterHashtable @{LogName = $logName; StartTime = $since; Level = 2} -MaxEvents 800 -ErrorAction SilentlyContinue)
    } catch {
        $evts = @(Get-EventLog -LogName $logName -EntryType Error -After $since -Newest 500 -ErrorAction SilentlyContinue)
    }
    Add-Line ('-- ' + $logName + ' 日志（错误/严重，共 ' + $evts.Count + ' 条）--')
    if ($evts.Count -eq 0) { Add-Line '  未发现错误记录。' }
    else {
        $top = 30
        if (-not $Fast) { $top = 60 }
        $groups = $evts | Group-Object Id | Sort-Object Count -Descending | Select-Object -First $top
        foreach ($g in $groups) {
            $e = $g.Group | Select-Object -First 1
            $src = ''
            if ($e.ProviderName) { $src = $e.ProviderName } elseif ($e.Source) { $src = $e.Source }
            $msg = ''
            if ($e.Message) { $msg = ($e.Message -replace '\s+', ' ') }
            if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 150) + '...' }
            Add-Line ('  EventID ' + $g.Name + '  [' + $src + '] x' + $g.Count + '  ' + $msg)
        }
    }
}

# ========== 5. 蓝屏与崩溃 ==========
Info '采集蓝屏信息'
Add-Section '5. 蓝屏与崩溃'
$md = Join-Path $env:WINDIR 'Minidump'
if (Test-Path $md) {
    $dumps = @(Get-ChildItem $md -Filter '*.dmp')
    if ($dumps.Count -gt 0) {
        Add-Line ('蓝屏转储 : ' + $dumps.Count + ' 个，最近:')
        $dumps | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
            Add-Line ('  - ' + $_.Name + '  ' + $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
        }
        Add-Finding 'R10' '高' '' '存在蓝屏转储文件' ('共 ' + $dumps.Count + ' 个 Minidump，建议使用 AI 分析具体原因')
    } else { Add-Line '蓝屏转储 : 无' }
} else { Add-Line '蓝屏转储 : 无 Minidump 目录' }
if (Test-Path (Join-Path $env:WINDIR 'MEMORY.DMP')) { Add-Line 'MEMORY.DMP : 存在（完整内存转储）' }
try {
    $wer = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = 1001} -MaxEvents 5 -ErrorAction Stop)
    if ($wer.Count -gt 0) {
        Add-Line '最近崩溃事件 (EventID 1001):'
        foreach ($w in $wer) {
            $m = ($w.Message -replace '\s+', ' ')
            if ($m.Length -gt 200) { $m = $m.Substring(0, 200) }
            Add-Line ('  - ' + $m)
        }
    }
} catch { }

# ========== 6. 驱动 ==========
Info '采集驱动状态'
Add-Section '6. 驱动与设备'
$badDev = @(Get-WmiObject Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
if ($badDev.Count -eq 0) { Add-Line '问题设备 : 无' }
else {
    Add-Line ('问题设备 : ' + $badDev.Count + ' 个')
    $badDev | Select-Object -First 10 | ForEach-Object {
        Add-Line ('  - [' + $_.ConfigManagerErrorCode + '] ' + $_.Name)
    }
}
$stoppedDrv = @(Get-WmiObject Win32_SystemDriver | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -eq 'Stopped' -and $_.PathName })
if ($stoppedDrv.Count -gt 0) {
    Add-Line ('自动启动但已停止的服务/驱动 : ' + $stoppedDrv.Count + ' 个，前 8:')
    $stoppedDrv | Select-Object -First 8 | ForEach-Object { Add-Line ('  - ' + $_.DisplayName + ' (' + $_.Name + ')') }
    Add-Finding 'R09' '中' '' '存在自动启动但停止的服务' ('共 ' + $stoppedDrv.Count + ' 个，建议结合 AI 分析或手动检查')
}

# ========== 7. 网络 ==========
Info '采集网络状态'
Add-Section '7. 网络'
$gwList = @()
$ncs = @(Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled })
foreach ($nc in $ncs) {
    if ($nc.DefaultIPGateway) { $gwList += $nc.DefaultIPGateway[0] }
}
if ($gwList.Count -gt 0) {
    $gw = $gwList[0]
    Add-Line ('默认网关 : ' + $gw)
    $pg = Test-Connection -ComputerName $gw -Count 2 -ErrorAction SilentlyContinue
    if ($pg) { Add-Line '网关连通 : 是' } else { Add-Line '网关连通 : 否（可能是网络协议栈问题）' }
}
$pingNet = Test-Connection -ComputerName '223.5.5.5' -Count 2 -ErrorAction SilentlyContinue
$pingWeb = Test-Connection -ComputerName 'www.baidu.com' -Count 1 -ErrorAction SilentlyContinue
Add-Line ('外网连通 : ' + $(if ($pingNet) { '是' } else { '否' }))
Add-Line ('域名解析 : ' + $(if ($pingWeb) { '正常' } else { '失败(DNS 可能有问题)' }))
if ($pingNet -and -not $pingWeb) {
    Add-Finding 'R02' '中' 'F01' 'DNS 解析失败' '能连通外网 IP 但域名解析失败，建议刷新 DNS'
} elseif (-not $pingNet -and $gwList.Count -gt 0) {
    Add-Finding 'R03' '中' 'F02' '网络连通异常' '外网不通，若网线/路由器正常则可能为网络协议栈问题，建议重置 Winsock/TCP-IP'
}
$proxy = (& netsh winhttp show proxy) -join "`r`n"
Add-Line 'WinHTTP 代理 :'
Add-Line ('  ' + $proxy)
if ($proxy -match 'Proxy Server\(s\)\s+:\s+\S+') {
    Add-Finding 'R04' '中' 'F03' 'WinHTTP 代理被设置' '系统中存在 WinHTTP 代理，可能被恶意软件设置，建议重置'
}
$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
if (Test-Path $hostsPath) {
    $h = Get-Item $hostsPath
    $hl = @(Get-Content $hostsPath | Where-Object { $_ -match '^\s*\S' -and $_ -notmatch '^\s*#' })
    Add-Line ('hosts 文件 : ' + $h.Length + ' 字节，' + $hl.Count + ' 条有效记录')
    if ($hl.Count -gt 100) { Add-Finding 'R01' '中' 'F04' 'hosts 文件异常' ('hosts 文件包含 ' + $hl.Count + ' 条记录，疑似被劫持，建议重置') }
} else { Add-Line 'hosts 文件 : 不存在' }
$netAdapters = @(Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -and $_.NetEnabled })
if ($netAdapters.Count -eq 0) { Add-Line '网卡      : 未发现已启用的物理网卡!' }
else { Add-Line ('网卡      : ' + (($netAdapters | ForEach-Object { $_.Name }) -join ' / ')) }
Add-Line 'IP 配置摘要 :'
Add-Line (Get-ConsoleText 'ipconfig /all')

# ========== 8. 启动项 ==========
Info '采集启动项'
Add-Section '8. 启动项与自启动服务'
$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)
$susCount = 0
foreach ($rk in $runKeys) {
    $item = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
    if ($item) {
        $vals = @($item.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })
        foreach ($v in $vals) {
            $data = [string]$v.Value
            Add-Line ('  [' + $rk + '] ' + $v.Name + ' -> ' + $data)
            if ($data -match '(?i)temp') {
                $susCount++
                Add-Finding 'R07' '中' 'F07' ('可疑启动项: ' + $v.Name) ($data + ' ;KEY=' + $rk + ';VAL=' + $v.Name)
            }
        }
    }
}
Add-Line ('可疑启动项计数: ' + $susCount + '（路径含 temp 的启动项）')
Add-Line '启动文件夹:'
$startupDirs = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
)
foreach ($sd in $startupDirs) {
    if (Test-Path $sd) {
        $f = @(Get-ChildItem $sd -ErrorAction SilentlyContinue)
        Add-Line ('  ' + $sd + ' : ' + $(if ($f.Count -gt 0) { (($f | ForEach-Object { $_.Name }) -join ', ') } else { '(空)' }))
    }
}
$winlogon = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
if ($winlogon) {
    Add-Line ('Winlogon Shell    : ' + $winlogon.Shell)
    Add-Line ('Winlogon Userinit : ' + $winlogon.Userinit)
}
$tasksText = Get-ConsoleText 'schtasks /query /fo csv /nh'
$tasks = @()
if ($tasksText) { $tasks = @($tasksText -split "`r`n" | Where-Object { $_.Trim() }) }
if ($tasks.Count -gt 0) {
    Add-Line ('计划任务 : 共 ' + $tasks.Count + ' 条（含系统任务，可疑项建议 AI 分析）')
} else {
    Add-Line '计划任务 : 查询失败（无法获取任务列表）'
}

# ========== 9. 更新 ==========
Info '采集更新状态'
Add-Section '9. Windows 更新'
$hot = @(Get-HotFix -ErrorAction SilentlyContinue)
if ($hot.Count -gt 0) {
    Add-Line ('已安装更新 : ' + $hot.Count + ' 个')
} else {
    Add-Line '已安装更新 : 查询失败（WMI/COM 不可用）'
}
$recent = @($hot | Where-Object { $_.InstalledOn -and $_.InstalledOn -gt (Get-Date).AddDays(-14) })
if ($recent.Count -gt 0) {
    Add-Line '近 14 天安装:'
    $recent | ForEach-Object { Add-Line ('  - ' + $_.HotFixID + '  ' + $_.InstalledOn.ToString('yyyy-MM-dd')) }
}
$sinceU = (Get-Date).AddDays(-30)
$uerr = @()
try {
    $uerr = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; StartTime = $sinceU; Level = 1} -MaxEvents 200 -ErrorAction Stop)
    $uerr += @(Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; StartTime = $sinceU; Level = 2} -MaxEvents 200 -ErrorAction SilentlyContinue)
} catch {
    $uerr = @(Get-EventLog -LogName System -Source 'Microsoft-Windows-WindowsUpdateClient' -EntryType Error -After $sinceU -Newest 200 -ErrorAction SilentlyContinue)
}
if ($uerr.Count -gt 0) {
    Add-Line ('近 30 天更新失败 : ' + $uerr.Count + ' 次')
    Add-Finding 'R12' '中' 'F08' 'Windows 更新反复失败' ('近 30 天 ' + $uerr.Count + ' 次更新失败，建议重置更新缓存')
} else { Add-Line '近 30 天更新失败 : 无' }

# ========== 10. 安全 ==========
Info '采集安全状态'
Add-Section '10. 安全状态'
# 防火墙：以可靠来源判定；判断不了就不报，避免误报
$fwKnown = $false
$fwOn = 0
try {
    $profs = @(Get-NetFirewallProfile -ErrorAction Stop)
    if ($profs.Count -gt 0) {
        foreach ($p in $profs) {
            $en = [string]$p.Enabled
            if ($en -match '(?i)^true$') { $fwOn++ }
            Add-Line ('防火墙配置 ' + $p.Name + ' : ' + $en)
        }
        $fwKnown = $true
    }
} catch { }
if (-not $fwKnown) {
    $fwRaw = (& netsh advfirewall show allprofiles state) -join "`r`n"
    if ($fwRaw -match '(?i)\bON\b|打开|启用') { Add-Line '防火墙 : 至少一个配置文件已开启'; $fwKnown = $true; $fwOn = 1 }
    elseif ($fwRaw -match '(?i)\bOFF\b|关闭|禁用') { Add-Line '防火墙 : 全部关闭'; $fwKnown = $true; $fwOn = 0 }
    else { Add-Line '防火墙 : 状态无法判断（权限不足或命令不支持，未做判定）' }
}
if ($fwKnown -and $fwOn -eq 0) { Add-Finding 'R14' '高' 'F13' 'Windows 防火墙已关闭' '所有防火墙配置文件均为关闭状态，建议重置并开启' }

# 杀毒 / Defender：以可靠状态为准，SecurityCenter 状态码仅作参考（避免误报）
$avCount = 0
$av = Get-WmiObject -Namespace 'root\SecurityCenter2' -Class AntiVirusProduct -ErrorAction SilentlyContinue
if ($av) {
    foreach ($a2 in $av) {
        $avCount++
        Add-Line ('杀毒产品 : ' + $a2.displayName + '（状态码 0x' + ('{0:X6}' -f [int]$a2.productState) + '，仅供参考）')
    }
} else { Add-Line '杀毒产品 : 未检测到已注册的杀毒软件' }
$defChecked = $false
if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    $ms = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($ms) {
        $defChecked = $true
        Add-Line ('Defender : 实时保护=' + $(if ($ms.RealTimeProtectionEnabled) { '开' } else { '关' }) + ' | 防病毒=' + $(if ($ms.AntivirusEnabled) { '开' } else { '关' }) + ' | 引擎=' + $ms.AMEngineVersion)
        if ((-not $ms.RealTimeProtectionEnabled) -and (-not $ms.AntivirusEnabled)) { Add-Finding 'R11' '高' '' 'Defender 实时保护与防病毒均未启用' 'Windows Defender 未在保护这台电脑，建议开启，或确认已安装第三方杀毒软件' }
        elseif (-not $ms.RealTimeProtectionEnabled) { Add-Finding 'R16' '中' 'F12' 'Defender 实时保护关闭' '防病毒引擎在运行但实时保护关闭，建议启用（F12）' }
    }
}
if ((-not $defChecked) -and ($avCount -eq 0)) { Add-Finding 'R11' '高' '' '未检测到杀毒软件' '既没有注册的杀毒产品，也无法读取 Defender 状态，请确认这台电脑是否装了安全软件' }
# ========== 11. 系统文件完整性（仅完整模式） ==========
if (-not $Fast) {
    Info '扫描系统文件完整性 (sfc, 约 2~10 分钟)'
    Add-Section '11. 系统文件完整性扫描'
    if ($IsAdmin) {
        $sfcOut = (& sfc /verifyonly) -join "`r`n"
        $sfcCode = $LASTEXITCODE
        Add-Line ('SFC 校验退出码 : ' + $sfcCode + '（0=完好）')
        $lines = @($sfcOut -split "`r`n" | Where-Object { $_.Trim() })
        Add-Line (($lines | Select-Object -Last 6) -join "`r`n")
        if ($sfcCode -ne 0) {
            Add-Finding 'R05' '中' 'F05' '系统文件存在损坏（SFC 检出）' ('sfc /verifyonly 退出码 ' + $sfcCode + '，建议执行 sfc /scannow 修复')
        }
        $osv = [Environment]::OSVersion.Version
        $isWin8plus = ($osv.Major -ge 10) -or ($osv.Major -eq 6 -and $osv.Minor -ge 2)
        if ($isWin8plus) {
            Info '扫描组件存储健康 (dism, 约 5~15 分钟)'
            $dismOut = (& dism /online /cleanup-image /scanhealth) -join "`r`n"
            $dismCode = $LASTEXITCODE
            Add-Line ('DISM ScanHealth 退出码 : ' + $dismCode + '（0=健康, 非0=可能可修复）')
            $dl = @($dismOut -split "`r`n" | Where-Object { $_.Trim() })
            Add-Line (($dl | Select-Object -Last 4) -join "`r`n")
            if ($dismCode -ne 0) {
                Add-Finding 'R06' '中' 'F06' '组件存储损坏（DISM 检出）' ('DISM ScanHealth 退出码 ' + $dismCode + '，建议 RestoreHealth 修复')
            }
        }
    } else {
        Add-Line '未以管理员身份运行，跳过 SFC/DISM 扫描。'
    }
}

# ========== 12. 打印与打印服务 ==========
Info '采集打印信息'
Add-Section '12. 打印与打印服务'
$hasTNC = [bool](Get-Command Test-NetConnection -ErrorAction SilentlyContinue)
$hasNA = [bool](Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)

$spooler = Get-Service Spooler -ErrorAction SilentlyContinue
if ($spooler) {
    Add-Line ('打印后台处理程序 Spooler : ' + $spooler.Status + ' (启动类型 ' + $spooler.StartType + ')')
    if ($spooler.Status -ne 'Running') { Add-Finding 'R20' '高' 'F14' '打印服务(Spooler)未运行' ('当前状态 ' + $spooler.Status + '，会导致完全无法打印') }
} else { Add-Line '打印后台处理程序 Spooler : 查询失败' }

$printers = @()
try { $printers = @(Get-Printer -ErrorAction Stop) } catch { $printers = @() }
if ($printers.Count -gt 0) {
    Add-Line ('已安装打印机 : ' + $printers.Count + ' 台')
    foreach ($p in $printers) {
        Add-Line ('  - ' + $p.Name + ' | 驱动=' + $p.DriverName + ' | 端口=' + $p.PortName + ' | 共享=' + $p.Shared + ' | 状态=' + $p.PrinterStatus)
    }
    $dupPorts = @($printers | Group-Object PortName | Where-Object { $_.Count -gt 1 -and $_.Name })
    foreach ($g in $dupPorts) { Add-Finding 'R22' '低' '' ('同一端口上安装了 ' + $g.Count + ' 台打印机(' + $g.Name + ')') '可能是重复安装的失效副本，建议在"设备和打印机"里清理多余项' }
} else {
    $wmip = @(Get-WmiObject Win32_Printer -ErrorAction SilentlyContinue)
    if ($wmip.Count -gt 0) {
        Add-Line ('已安装打印机 : ' + $wmip.Count + ' 台（WMI 查询）')
        foreach ($p in $wmip) { Add-Line ('  - ' + $p.Name + ' | 驱动=' + $p.DriverName + ' | 端口=' + $p.PortName + ' | 共享=' + $p.Shared + ' | 网络=' + $p.Network) }
    } else { Add-Line '已安装打印机 : 无（或查询失败）' }
}

$defP = @()
try { $defP = @(Get-WmiObject Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Default }) } catch { }
if ($defP.Count -gt 0) { Add-Line ('默认打印机 : ' + (($defP | ForEach-Object { $_.Name }) -join ', ')) }
elseif ($printers.Count -gt 0) { Add-Finding 'R21' '低' '' '没有设置默认打印机' 'Office 等程序可能提示"未安装打印机"，建议在"设备和打印机"里指定默认打印机' }

$jobs = @()
try { $jobs = @(Get-PrintJob -PrinterName * -ErrorAction Stop) } catch { }
if ($jobs.Count -gt 0) {
    Add-Line ('打印队列 : ' + $jobs.Count + ' 个任务')
    foreach ($j in ($jobs | Select-Object -First 8)) { Add-Line ('  - ' + $j.PrinterName + ' | ' + $j.DocumentName + ' | ' + $j.JobStatus + ' | ' + $j.SubmittedTime) }
    $stuck = @($jobs | Where-Object { $_.SubmittedTime -and ($_.SubmittedTime -lt (Get-Date).AddMinutes(-10)) })
    if ($stuck.Count -gt 0) { Add-Finding 'R24' '中' 'F14' ('打印队列有 ' + $stuck.Count + ' 个超过 10 分钟未完成的任务') '队列可能被卡死任务阻塞（清队列会丢失未打印任务，执行前请确认）' }
} else { Add-Line '打印队列 : 空（或无法查询）' }

$ports = @()
try { $ports = @(Get-PrinterPort -ErrorAction Stop) } catch { }
if ($ports.Count -gt 0) {
    Add-Line '打印端口:'
    foreach ($pt in $ports) {
        Add-Line ('  - ' + $pt.Name + ' | 地址=' + $pt.PrinterHostAddress + ' | 协议=' + $pt.Protocol + ' | 端口号=' + $pt.PortNumber)
        if (($pt.Protocol -eq 'WSD') -or ($pt.Name -match '(?i)wsd')) {
            Add-Finding 'R23' '中' 'F19' ('存在 WSD 打印端口: ' + $pt.Name) 'WSD 在校园网络（跨网段/多播受限）里容易时好时坏，建议改用标准 RAW 9100 端口'
        }
        if ($pt.PrinterHostAddress -and $hasTNC) {
            $ok = $null
            try { $ok = Test-NetConnection -ComputerName $pt.PrinterHostAddress -Port 9100 -InformationLevel Quiet -ErrorAction Stop } catch { }
            if ($ok -eq $false) { Add-Finding 'R25' '中' '' ('打印机主机 ' + $pt.PrinterHostAddress + ' 的 9100 端口不通') '检查打印机电源/网线/是否换过 IP；若在别的网段可能需要打印服务器' }
            $smb = $null
            try { $smb = Test-NetConnection -ComputerName $pt.PrinterHostAddress -Port 445 -InformationLevel Quiet -ErrorAction Stop } catch { }
            if ($smb -eq $false) { Add-Finding 'R26' '中' '' ('打印机主机 ' + $pt.PrinterHostAddress + ' 的 SMB(445) 不通') '共享打印机连不上时先看这条：对方是否开机、共享是否开启、防火墙是否拦 445' }
        }
    }
} else { Add-Line '打印端口 : 无法查询（需要 Win8+ 或 PrintManagement 模块）' }

$shared = @($printers | Where-Object { $_.Shared })
if ($shared.Count -gt 0) { Add-Line ('本机共享的打印机 : ' + $shared.Count + ' 台') }
$rpv = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' -Name RpcAuthnLevelPrivacyEnabled -ErrorAction SilentlyContinue).RpcAuthnLevelPrivacyEnabled
Add-Line ('共享打印兼容键 RpcAuthnLevelPrivacyEnabled : ' + $(if ($null -eq $rpv) { '未设置（默认视为 1）' } else { $rpv }))
if ($shared.Count -gt 0) { Add-Finding 'R27' '低' 'F18' '本机共享了打印机' '若客户端连接时报 0x0000011b，可在校方允许的前提下执行 F18（属安全权衡）' }

# ========== 13. 校园网接入（802.1X / DHCP / 代理 / 虚拟网卡） ==========
Info '采集校园网接入信息'
Add-Section '13. 校园网接入（认证/DHCP/代理/虚拟网卡）'

$phys = @()
if ($hasNA) { try { $phys = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue) } catch { } }
if ($phys.Count -gt 0) {
    foreach ($a in $phys) {
        Add-Line ('物理网卡 ' + $a.Name + ' : ' + $a.Status + ' / ' + $a.LinkSpeed + ' / ' + $a.InterfaceDescription)
        if ($a.Status -eq 'Disabled') { Add-Finding 'R28' '高' 'F17' ('网卡被禁用: ' + $a.Name) '网卡处于"已禁用"状态，任何网络都不通' }
    }
} else {
    $wna = @(Get-WmiObject Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalAdapter -and $_.NetConnectionID })
    foreach ($a in $wna) { Add-Line ('物理网卡 ' + $a.NetConnectionID + ' : NetEnabled=' + $a.NetEnabled + ' / ' + $a.Name) ; if ($a.NetEnabled -eq $false) { Add-Finding 'R28' '高' 'F17' ('网卡被禁用: ' + $a.NetConnectionID) '网卡处于禁用状态' } }
}

$cfgs = @(Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPEnabled })
foreach ($c in $cfgs) {
    $na = Get-WmiObject Win32_NetworkAdapter -Filter ('Index=' + $c.Index) -ErrorAction SilentlyContinue
    $nm = $na.NetConnectionID
    $ips4 = @($c.IPAddress | Where-Object { $_ -match '^\d+\.' })
    $gws = @($c.DefaultIPGateway | Where-Object { $_ })
    $dnss = @($c.DNSServerSearchOrder | Where-Object { $_ })
    Add-Line ('接口 ' + $nm + ' : DHCP=' + $c.DHCPEnabled + ' | IP=' + ($ips4 -join ', ') + ' | 网关=' + ($gws -join ', ') + ' | DNS=' + ($dnss -join ', '))
    foreach ($ip in $ips4) {
        if ($ip -like '169.254.*') { Add-Finding 'R29' '高' 'F15' ('接口 ' + $nm + ' 未获取到有效 IP（169.254.x.x）') 'DHCP 失败。校园网下通常是 802.1X 认证未通过或该网口未放行：先确认认证客户端已登录，再审慎使用 F15 续租' }
    }
    $isVirtualNic = $false
    if ($nm -match '(?i)vmware|virtualbox|radmin|tap|tun|wireguard|openvpn|zerotier|clash|vpn|host-only|loopback|bluetooth|蓝牙') { $isVirtualNic = $true }
    if ($na -and ($na.Name -match '(?i)vmware|virtualbox|radmin|tap|tun|host-only|vpn|loopback')) { $isVirtualNic = $true }
    if ($gws.Count -eq 0 -and $ips4.Count -gt 0 -and $ips4[0] -notlike '169.254.*' -and -not $isVirtualNic) { Add-Finding 'R30' '中' '' ('接口 ' + $nm + ' 没有默认网关') '可能是静态配置错误或 DHCP 半失败，建议核对网络配置' }
    foreach ($d in $dnss) { if ($d -match '^(127\.0\.0\.1|0\.0\.0\.0)$') { Add-Finding 'R31' '中' 'F16' ('DNS 指向无效地址: ' + $d) 'DNS 被代理软件/加速器改坏，建议改回自动获取并清理代理' } }
}

$whp = (& netsh winhttp show proxy) -join ' '
Add-Line ('WinHTTP 代理 : ' + $whp)
$iep = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($iep) { Add-Line ('IE 代理 : ProxyEnable=' + $iep.ProxyEnable + ' | ProxyServer=' + $iep.ProxyServer) }
$envProxies = @(Get-ChildItem env: -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)proxy' })
foreach ($e in $envProxies) { Add-Line ('代理环境变量 ' + $e.Name + ' = ' + $e.Value) }
$proxySet = (($whp -match 'Proxy Server\(s\)\s+:\s+\S+') -or ($iep -and $iep.ProxyEnable -eq 1) -or ($envProxies.Count -gt 0))
if ($proxySet) { Add-Finding 'R32' '中' 'F16' '存在代理设置（含环境变量）' '加速器/旧代理残留会导致"能连网但打不开网页"；如非学校要求可执行 F16 清理（会先备份原值）' }

$virt = @()
if ($hasNA) { try { $virt = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match '(?i)vmware|virtualbox|radmin|tap|tun|wireguard|openvpn|zerotier|clash|加速|vpn' }) } catch { } }
if ($virt.Count -gt 0) { Add-Line ('虚拟/VPN 网卡 : ' + (($virt | ForEach-Object { $_.Name + '(' + $_.Status + ')' }) -join ', ')) }
$defRoute = @()
try { $defRoute = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop) } catch { }
if ($defRoute.Count -gt 0) {
    foreach ($r in $defRoute) { Add-Line ('默认路由 : ' + $r.InterfaceAlias + ' -> ' + $r.NextHop + ' (metric ' + $r.RouteMetric + ')') }
    $eff = @($defRoute | Sort-Object RouteMetric | Select-Object -First 1)
    $virtNames = @($virt | ForEach-Object { $_.Name })
    if ($eff.Count -gt 0) {
        Add-Line ('生效默认路由 : ' + $eff[0].InterfaceAlias + ' (metric ' + $eff[0].RouteMetric + ')')
        if ($virtNames -contains $eff[0].InterfaceAlias) {
            Add-Finding 'R33' '高' '' ('实际生效的默认路由指向虚拟网卡: ' + $eff[0].InterfaceAlias) '这是"连着网但打不开网页"的经典原因：建议临时禁用该虚拟网卡（不要删除）'
        }
    }
}

$pat = 'ruijie|supplicant|srun|inode|drcom|8021x|h3c|锐捷|深澜|认证'
$cli = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $pat })
$csvc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat -or $_.DisplayName -match $pat })
if ($cli.Count -gt 0) { Add-Line ('认证客户端进程 : ' + (($cli | ForEach-Object { $_.ProcessName }) -join ', ')) } else { Add-Line '认证客户端进程 : 未发现' }
if ($csvc.Count -gt 0) {
    foreach ($s in $csvc) { Add-Line ('认证相关服务 : ' + $s.Name + ' (' + $s.DisplayName + ') = ' + $s.Status) }
    $stopped = @($csvc | Where-Object { $_.Status -ne 'Running' })
    if ($stopped.Count -gt 0 -and $cli.Count -eq 0) { Add-Finding 'R34' '中' 'F21' '校园网认证客户端未运行' '检测到认证相关服务存在但已停止，可尝试 F21 重启服务（只重启，不重装）' }
} else { Add-Line '认证相关服务 : 未发现（若校园网要求 802.1X，需先安装学校指定的认证客户端）' }

try {
    $conf = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-Tcpip'; StartTime = (Get-Date).AddDays(-7)} -MaxEvents 200 -ErrorAction Stop | Where-Object { $_.Id -eq 4198 -or $_.Id -eq 4199 })
    if ($conf.Count -gt 0) { Add-Line ('近 7 天 IP 冲突事件 : ' + $conf.Count + ' 条'); Add-Finding 'R35' '高' '' '检测到 IP 地址冲突' '本机 IP 与他人冲突，应改为自动获取或联系网管重新分配' } else { Add-Line '近 7 天 IP 冲突事件 : 无' }
} catch { Add-Line '近 7 天 IP 冲突事件 : 查询失败' }
# ========== 14. 规则诊断汇总 ==========
Add-Section '14. 规则诊断结果'
if ($script:Findings.Count -eq 0) {
    Add-Line '本地规则未发现已知问题。建议使用 AI 智能分析进一步排查。'
} else {
    foreach ($f in $script:Findings) {
        $sugg = '人工/AI 判断'
        if ($f[2]) { $sugg = $f[2] }
        Add-Line ('[' + $f[0] + '] 严重度:' + $f[1] + '  ' + $f[3] + '  (建议修复: ' + $sugg + ')')
        Add-Line ('    ' + $f[4])
    }
}

# --- 落盘 ---
$text = $sb.ToString()
Out-File -FilePath $ReportFile -InputObject $text -Encoding UTF8
if ($script:Findings.Count -gt 0) {
    $fl = @($script:Findings | ForEach-Object { $_ -join '|' })
    Out-File -FilePath $FindingsFile -InputObject $fl -Encoding UTF8
} else {
    Out-File -FilePath $FindingsFile -InputObject '' -Encoding UTF8
}
$esc = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
$html = '<html><head><meta charset="utf-8"><title>Pi Agent 诊断报告</title>'
$html += '<style>body{font-family:Consolas,"Microsoft YaHei",monospace;margin:20px;background:#f4f6f8}'
$html += 'pre{white-space:pre-wrap;background:#fff;padding:18px;border:1px solid #d8dee4;border-radius:8px;font-size:13px;line-height:1.5}</style>'
$html += '</head><body><h2>Pi Agent 诊断报告</h2><pre>' + $esc + '</pre></body></html>'
Out-File -FilePath $HtmlFile -InputObject $html -Encoding UTF8

Write-Host ''
Write-Host ('体检完成！报告目录: ' + $OutDir)
Write-Host '  diagnosis.txt / diagnosis.html / findings.ini'
Write-Host ('本地规则发现 ' + $script:Findings.Count + ' 个问题。')

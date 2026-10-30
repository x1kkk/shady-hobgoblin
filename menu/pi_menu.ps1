# ============================================================
# Pi Agent - Pi 模式菜单（校园版 · 分类专项检修）
# 说明：本机环境变量存在大小写重复（NO_PROXY/no_proxy 等），会让
# PowerShell 的 Start-Process 抛异常，因此全部改用 .NET 原生 Process。
# 参数 -NoElevate：跳过提权与 Windows Terminal 切换（测试用）。
# ============================================================
param([switch]$NoElevate)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Root = (Get-Item (Join-Path $ScriptDir '..')).FullName
# A source-only checkout must still offer local diagnostics without an API or AI runtime.
if (-not (Test-Path -LiteralPath (Join-Path $Root 'runtime\pi\node.exe')) -or -not (Test-Path -LiteralPath (Join-Path $Root 'runtime\pi\node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js'))) {
    & (Join-Path $Root 'menu\main_menu.ps1') -NoElevate:$NoElevate
    exit
}

# ===== PATH 修复：pi 的 shell 工具依赖 PATH 里有 PowerShell =====
$psDir = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0'
if ((Test-Path $psDir) -and ($env:Path -notmatch [regex]::Escape($psDir))) {
    $env:Path = $psDir + ';' + (Join-Path $env:SystemRoot 'System32') + ';' + $env:Path
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# .NET 原生启动（绕开 Start-Process 的环境字典缺陷）
function Start-Native([string]$exe, [string]$arguments, [switch]$Elevate) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $true
    if ($Elevate) { $psi.Verb = 'runas' }
    return [System.Diagnostics.Process]::Start($psi)
}

# --- 提权（失败则降级为非管理员模式继续）---
if ((-not (Test-Admin)) -and (-not $NoElevate)) {
    Write-Host 'Pi Agent 需要管理员权限，正在请求（请在弹窗中点“是”）...'
    $myPath = $MyInvocation.MyCommand.Path
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $psExe)) { $psExe = 'powershell' }
    $elevated = $false
    try {
        [void](Start-Native $psExe ('-NoProfile -ExecutionPolicy Bypass -File "' + $myPath + '"') -Elevate)
        $elevated = $true
    } catch {
        Write-Host ''
        Write-Host '未能获得管理员权限（授权被取消或失败）。' -ForegroundColor Yellow
        Write-Host '将以“非管理员模式”继续：只读体检可用，修复功能不可用。' -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    if ($elevated) { exit }
}

# --- 自动切换到 Windows Terminal（修正中文宽字符导致的 TUI 渲染错位）---
if ((-not $env:WT_SESSION) -and (-not $NoElevate)) {
    $wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path $wt) {
        $psExe2 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $psExe2)) { $psExe2 = 'powershell' }
        try {
            Write-Host '正在切换到 Windows Terminal 以正确显示中文界面...'
            [void](Start-Native $wt ('-w 0 new-tab --title "Pi Agent 维修助手" "' + $psExe2 + '" -NoProfile -ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Path + '"'))
            Start-Sleep -Milliseconds 800
            exit
        } catch { }
    }
}

function Get-KeyStatus {
    $auth = Join-Path $Root 'pi-home\agent\auth.json'
    if (-not (Test-Path $auth)) { return '未配置（Pi 内 /login 或编辑 pi-home\agent\auth.json）' }
    try {
        $a = Get-Content $auth -Raw | ConvertFrom-Json
        $providers = @($a.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name })
        if ($providers.Count -gt 0) { return ('已配置: ' + ($providers -join ', ')) }
        return '文件为空'
    } catch { return '文件存在但解析失败' }
}

function Get-LatestReportDir {
    $rd = Join-Path $Root 'reports'
    if (-not (Test-Path $rd)) { return $null }
    $dirs = @(Get-ChildItem $rd | Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending)
    if ($dirs.Count -eq 0) { return $null }
    return $dirs[0]
}

function Set-PiEnv {
    $env:PI_CODING_AGENT_DIR = Join-Path $Root 'pi-home\agent'
    $env:PI_CODING_AGENT_SESSION_DIR = Join-Path $Root 'pi-home\agent\sessions'
    $env:PI_TELEMETRY = '0'
    $env:PI_SKIP_VERSION_CHECK = '1'
    # 中文输入法定位：显示硬件光标
    $env:PI_HARDWARE_CURSOR = '1'
    # 自带临时目录：避免依赖系统 %TEMP%（某些机器的 %TEMP%\jiti 有异常 ACL 会导致扩展编译失败）
    $tmpDir = Join-Path $Root 'logs\tmp'
    try {
        if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null }
        $env:TEMP = $tmpDir
        $env:TMP = $tmpDir
    } catch { }
}

# 用指定提示词启动 pi（交互式），实现“按类别针对性检修”
function Start-PiWithPrompt([string]$promptFile, [string]$title) {
    if (-not (Test-Path $promptFile)) {
        Write-Host ('缺少提示词文件：' + $promptFile) -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host ('正在启动：' + $title) -ForegroundColor Cyan
    Write-Host '提示：/login 登录模型、/model 切换模型、Ctrl+C 两次退出。' -ForegroundColor Gray
    Write-Host ''
    Set-PiEnv
    $piCmd = Join-Path $Root 'runtime\pi\pi.cmd'
    $reportsDir = Join-Path $Root 'reports'
    $beforeNames = @()
    if (Test-Path $reportsDir) { $beforeNames = @(Get-ChildItem $reportsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
    & cmd /c ('chcp 65001 >nul & cd /d "' + $Root + '" & "' + $piCmd + '" "@' + $promptFile + '"' + $piExtra)
    Invoke-ArchiveAfterTask $reportsDir $beforeNames
}

# 纯净模式：不加载维修准则、不预置任务
function Start-PiPlain {
    Write-Host ''
    Write-Host '正在启动 pi（纯净模式）：不加载维修准则 AGENTS.md、不预置任务，直接对话。' -ForegroundColor Cyan
    Write-Host '提示：/login 登录模型、/model 切换模型、/help 查看命令、Ctrl+C 两次退出。' -ForegroundColor Gray
    Write-Host ''
    Set-PiEnv
    $piCmd = Join-Path $Root 'runtime\pi\pi.cmd'
    $reportsDir = Join-Path $Root 'reports'
    $beforeNames = @()
    if (Test-Path $reportsDir) { $beforeNames = @(Get-ChildItem $reportsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
    & cmd /c ('chcp 65001 >nul & cd /d "' + $Root + '" & "' + $piCmd + '" --no-context-files' + $piExtra)
    Invoke-ArchiveAfterTask $reportsDir $beforeNames
}

# Archive consent is local configuration; absent configuration disables automatic uploads.
function Get-ArchiveConfig {
    $path = Join-Path $Root 'archive.local.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { return $null }
}
function Get-ArchiveRepo {
    $config = Get-ArchiveConfig
    if ($config -and $config.enabled -and $config.repoDir) { return [string]$config.repoDir }
    return ''
}

# ===== 归档状态与自动归档（agent 任务结束后可见）=====
function Show-ArchiveStatus {
    $rj = Join-Path $Root 'logs\archive-last-result.json'
    if (-not (Test-Path $rj)) { return '归档  : 尚未归档（出单/选 [12] 后自动上传）' }
    try {
        $j = Get-Content $rj -Raw -Encoding UTF8 | ConvertFrom-Json
        $mark = if ($j.pushed) { '✓ ' + $j.pushText } elseif ($j.pushText -match '无新记录|仅本地') { '· ' + $j.pushText } elseif ($j.pushText) { '! ' + $j.pushText } else { '· 无变化' }
        return ('归档  : ' + $j.time + '  新归档 ' + $j.archived + ' 条 / 已有 ' + $j.skipped + ' 条   ' + $mark)
    } catch { return '归档  : 状态读取失败' }
}

function Invoke-AutoArchive {
    $arch = Join-Path $Root 'tools\archive_records.ps1'
    $repo = Get-ArchiveRepo
    if (-not $repo) { Write-Host '归档尚未由用户配置。'; return }
    if (-not (Test-Path $arch)) { Write-Host '未找到归档脚本 tools\archive_records.ps1' -ForegroundColor Yellow; return }
    if (-not (Test-Path (Join-Path $repo '.git'))) { Write-Host '归档仓库未初始化（tools\setup_archive.ps1）' -ForegroundColor Yellow; return }
    Write-Host ''
    Write-Host '+--------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '|  维修记录归档  →  Gitee 私有仓库                              |' -ForegroundColor Cyan
    Write-Host '|  内容：工单 + AI 分析 + 解决办法                              |' -ForegroundColor DarkGray
    Write-Host '+--------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File $arch -Root $Root -Latest
    Write-Host ''
    Write-Host (' ' + (Show-ArchiveStatus)) -ForegroundColor DarkGray
    Write-Host ' 菜单 [12] = 补归档 / 补推（离线恢复网络时用）' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ArchiveAfterTask([string]$reportsDir, [string[]]$beforeNames) {
    try {
        $config = Get-ArchiveConfig
        if (-not $config -or -not $config.enabled -or -not $config.autoArchive) { return }
        if (-not (Test-Path $reportsDir)) { return }
        $after = @(Get-ChildItem $reportsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        $newDirs = @($after | Where-Object { $beforeNames -notcontains $_ })
        Write-Host ''
        if ($newDirs.Count -eq 0) {
            Write-Host '本次会话未生成新的体检报告 → 无新记录需要归档。' -ForegroundColor DarkGray
            Write-Host (' ' + (Show-ArchiveStatus)) -ForegroundColor DarkGray
            return
        }
        Write-Host ('本次会话新增体检报告 ' + $newDirs.Count + ' 份（最新：' + ($newDirs | Sort-Object | Select-Object -Last 1) + '）') -ForegroundColor DarkCyan
        Invoke-AutoArchive
    } catch {
        Write-Host ('归档过程异常：' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# 输出本次维修工单：有报告就总结本次工作；没开始工作则明确提示
function Show-Ticket {
    $latest = Get-LatestReportDir
    if (-not $latest) {
        Write-Host ''
        Write-Host '【还未开始执行任务】还没有任何体检报告。' -ForegroundColor Yellow
        Write-Host '请先选择 [1] 通用维修助手，或 [3]~[8] 任意专项检修；' -ForegroundColor Yellow
        Write-Host '完成体检/处理后，再回到本选项生成工单。' -ForegroundColor Yellow
        return
    }
    $diag = Join-Path $latest.FullName 'diagnosis.txt'
    if (-not (Test-Path $diag)) {
        Write-Host ''
        Write-Host ('【还未开始执行任务】最新目录 ' + $latest.Name + ' 里没有体检报告。') -ForegroundColor Yellow
        Write-Host '请先做一次体检（[1] 或 [3]~[8]），再来生成工单。' -ForegroundColor Yellow
        return
    }
    $old = @(Get-ChildItem $latest.FullName -Filter '工单*.txt' -ErrorAction SilentlyContinue)
    if ($old.Count -gt 0) {
        Write-Host ''
        Write-Host ('本次已生成过 ' + $old.Count + ' 份工单：' + (($old | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Cyan
        $ans = Read-Host '再生成一份新的吗？(y/N)'
        if (($ans -ne 'y') -and ($ans -ne 'Y')) { Write-Host '已保留原有工单。'; return }
    }
    Write-Host ''
    Write-Host '接下来请先给这份工单命名，再填写位置 / 报修人 / 处理人。' -ForegroundColor Gray
    Write-Host ''
    Write-Host ('正在总结本次工作并生成工单（依据报告：' + $latest.Name + '）...') -ForegroundColor Cyan
    & (Join-Path $Root 'core\ps\ticket.ps1') -Root $Root
    # 出工单后立即归档（每组维修后上传；未初始化仓库则静默跳过）
    try {
        $archScript = Join-Path $Root 'tools\archive_records.ps1'
        $archRepo = Get-ArchiveRepo
        $config = Get-ArchiveConfig
        if ($archRepo -and $config.autoArchive -and (Test-Path $archScript) -and (Test-Path (Join-Path $archRepo '.git'))) {
            Write-Host ''
            Write-Host '正在归档本次维修记录（工单 + AI 分析 + 解决办法）…' -ForegroundColor Cyan
            & powershell -NoProfile -ExecutionPolicy Bypass -File $archScript -Root $Root -Latest
        }
    } catch { }
}
# ===== 归档本次维修（出工单后自动上传）=====
function Start-Archive {
    $arch = Join-Path $Root 'tools\archive_records.ps1'
    if (-not (Test-Path $arch)) { Write-Host '未找到归档脚本：tools\archive_records.ps1' -ForegroundColor Yellow; return }
    $repo = Get-ArchiveRepo
    if (-not $repo) { Write-Host '归档尚未由用户配置。'; return }
    if (-not (Test-Path (Join-Path $repo '.git'))) {
        Write-Host ''
        Write-Host '归档仓库尚未初始化。请先执行一次：' -ForegroundColor Yellow
        Write-Host ('  powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'tools\setup_archive.ps1') + '" -RemoteUrl <自己的私有仓库URL> -AllowRemote') -ForegroundColor Yellow
        return
    }
    Clear-Host
    Write-Host '===== 归档维修记录（工单 + AI 分析 + 解决办法）=====' -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $arch -Root $Root -All
    Write-Host ''
    Write-Host '完成。详细日志：logs\archive.log' -ForegroundColor Gray
}
function Start-ScriptMenu {
    & (Join-Path $Root 'menu\main_menu.ps1') -NoElevate
}

# 各分类的专项提示词（复用 pi-home 下已有文件）
$P = @{
    general = Join-Path $Root 'pi-home\start_prompt.txt'
    print   = Join-Path $Root 'pi-home\prompt_print.txt'
    net     = Join-Path $Root 'pi-home\prompt_net.txt'
    sys     = Join-Path $Root 'pi-home\prompt_sys.txt'
    sec     = Join-Path $Root 'pi-home\prompt_sec.txt'
    disk    = Join-Path $Root 'pi-home\prompt_disk.txt'
    av      = Join-Path $Root 'pi-home\prompt_av.txt'
}

# ===== 开场动画（每次启动只播一次；config.ini 里 skip_intro=1 可关闭）=====
try { & (Join-Path $Root 'menu\intro.ps1') -Root $Root } catch { }

# ===== TUI 渲染参数 =====
# config.ini 中 tui_mode=regular|fullscreen；留空则自动选择：
#   有 Windows Terminal -> regular（默认渲染，体验最佳）
#   仅 conhost（老式控制台）-> fullscreen（备用屏 + 绝对定位重绘，规避宽字符光标漂移）
$piExtra = ''
try {
    $cfgMode = ''
    $cfgPath = Join-Path $Root 'config.ini'
    if (Test-Path $cfgPath) {
        foreach ($ln in @(Get-Content $cfgPath -ErrorAction SilentlyContinue)) {
            if ($ln -match '^\s*tui_mode\s*=\s*(\w+)') { $cfgMode = $Matches[1].ToLower() }
        }
    }
    if ($cfgMode -ne 'regular' -and $cfgMode -ne 'fullscreen') {
        # Windows 默认 fullscreen：编辑框/状态栏固定在底部，避免宽字符重绘造成的输入框漂移
        $cfgMode = 'fullscreen'
    }
    $piExtra = ' --tui-mode ' + $cfgMode
} catch { }
# 窄窗口宽字符换行易导致渲染漂移（<100 列）
try {
    if ($Host.UI.RawUI.WindowSize.Width -lt 100) {
        Write-Host '提示：当前窗口较窄（<100 列），中文宽字符可能显示错位；建议最大化窗口或改用 Windows Terminal。' -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1500
    }
} catch { }

# ===== 开场动画 =====
$Host.UI.RawUI.WindowTitle = 'Pi Agent 维修助手 (校园版)'

while ($true) {
    Clear-Host
    Write-Host '==============================================='
    Write-Host '   Pi Agent 维修助手  ——  校园版'
    Write-Host '   办公电脑 / 学生笔记本 · 分类专项检修'
    Write-Host '==============================================='
    Write-Host ('   DeepSeek Key : ' + (Get-KeyStatus))
    if (-not (Test-Admin)) { Write-Host '   权限         : 非管理员（修复功能不可用）' -ForegroundColor Yellow }
    Write-Host ('   ' + (Show-ArchiveStatus)) -ForegroundColor DarkCyan
    Write-Host '-----------------------------------------------'
    Write-Host '   [1] 通用维修助手（先体检，再给结论与建议）'
    Write-Host '   [2] 纯净模式（不预置任务，当通用 AI 用）'
    Write-Host '   ---------- 校园专项检修（针对性） ----------'
    Write-Host '   [3] 打印机专项（共享/网络/队列/0x0000011b）'
    Write-Host '   [4] 校园网专项（认证/DHCP/DNS/代理/虚拟网卡）'
    Write-Host '   [5] 系统与性能专项（慢/卡/蓝屏/启动项）'
    Write-Host '   [6] 安全专项（防火墙/杀毒/hosts/启动项）'
    Write-Host '   [7] 磁盘与数据专项（空间/SMART/备份提醒）'
    Write-Host '   [8] 多媒体教室专项（投影/双屏/音响）'
    Write-Host '   ---------------------------------------------'
    Write-Host '   [9] 输出维修工单（总结本次处理，可登记/上报）'
    Write-Host '   [10] 传统脚本菜单（无 AI，Win7 亦可用）'
    Write-Host '   [11] 使用说明            [12] 归档维修记录（上传 Gitee）'
    Write-Host '   [0] 退出'
    Write-Host '==============================================='
    $choice = Read-Host '请选择'
    switch ($choice) {
        '1' { Start-PiWithPrompt $P.general '通用维修助手' }
        '2' { Start-PiPlain }
        '3' { Start-PiWithPrompt $P.print '打印机专项检修' }
        '4' { Start-PiWithPrompt $P.net '校园网专项检修' }
        '5' { Start-PiWithPrompt $P.sys '系统与性能专项检修' }
        '6' { Start-PiWithPrompt $P.sec '安全专项检修' }
        '7' { Start-PiWithPrompt $P.disk '磁盘与数据专项检修' }
        '8' { Start-PiWithPrompt $P.av '多媒体教室专项检修' }
        '9' { Show-Ticket }
        '10' { Start-ScriptMenu }
        '11' { $h = Join-Path $Root '使用说明.txt'; if (Test-Path $h) { Invoke-Item $h } }
        '12' { Start-Archive }
        '0' { exit 0 }
        default { }
    }
    Write-Host ''
    Read-Host '按回车键返回菜单' | Out-Null
}
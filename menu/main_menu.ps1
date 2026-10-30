# ============================================================
# Pi Agent - 中文主菜单 (main_menu.ps1)
# 兼容 Windows PowerShell 2.0+ (Win7/2008 及以上)
# 双击 start.bat 会启动本菜单；需要管理员权限时会自动提权。
# ============================================================
param([switch]$NoElevate)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Root = (Get-Item (Join-Path $ScriptDir '..')).FullName

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- 自动提权 ---
if ((-not (Test-Admin)) -and (-not $NoElevate)) {
    Write-Host 'Pi Agent 需要管理员权限，正在请求（请在弹窗中点“是”）...'
    $myPath = $MyInvocation.MyCommand.Path
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $psExe)) { $psExe = 'powershell' }
    $elevated = $false
    try {
        $psiE = New-Object System.Diagnostics.ProcessStartInfo
        $psiE.FileName = $psExe
        $psiE.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $myPath + '"'
        $psiE.UseShellExecute = $true
        $psiE.Verb = 'runas'
        [void][System.Diagnostics.Process]::Start($psiE)
        $elevated = $true
    } catch {
        Write-Host ''
        Write-Host '未能获得管理员权限（授权被取消或失败）。' -ForegroundColor Yellow
        Write-Host '将以“非管理员模式”继续：只读体检可用，修复功能不可用。' -ForegroundColor Yellow
        Write-Host '如需完整功能，请在“终端(管理员)”里运行本菜单。' -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    if ($elevated) { exit }
}

function Get-LatestReportDir {
    $rd = Join-Path $Root 'reports'
    if (-not (Test-Path $rd)) { return $null }
    $dirs = @(Get-ChildItem $rd | Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending)
    if ($dirs.Count -eq 0) { return $null }
    return $dirs[0]
}

function Get-ApiKey {
    $cfg = Join-Path $Root 'config.ini'
    if (-not (Test-Path $cfg)) { return '' }
    $line = Get-Content $cfg -Encoding ASCII | Where-Object { $_ -match '^api_key\s*=' } | Select-Object -First 1
    if ($line) { return ($line -replace '^api_key\s*=', '').Trim() }
    return ''
}

function Set-ApiKey {
    Write-Host '请输入 DeepSeek API Key（输入时屏幕不显示）:'
    $s = Read-Host -AsSecureString
    if (-not $s) { Write-Host '已取消。'; return }
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    if ($key.Trim() -eq '') { Write-Host 'Key 为空，已取消。'; return }
    $cfg = Join-Path $Root 'config.ini'
    $lines = @()
    if (Test-Path $cfg) { $lines = @(Get-Content $cfg -Encoding ASCII) } else { $lines = @('[deepseek]', 'api_key=', 'model=deepseek-chat', 'base_url=https://api.deepseek.com') }
    $out = @()
    foreach ($l in $lines) {
        if ($l -match '^api_key\s*=') { $out += 'api_key=' + $key } else { $out += $l }
    }
    Out-File -FilePath $cfg -InputObject $out -Encoding ASCII
    Write-Host '已保存到 config.ini。注意：明文存储，U盘丢失请到 DeepSeek 后台吊销该 Key。'
}

function Invoke-Collect([bool]$fast) {
    $ErrorActionPreference = 'Continue'
    Write-Host ''
    if ($fast) { Write-Host '开始快速体检（约 1 分钟）...' } else { Write-Host '开始完整体检（含 sfc/DISM 扫描，约 5~15 分钟）...' }
    Write-Host ''
    & (Join-Path $Root 'core\ps\collect.ps1') -Root $Root -Fast:$fast
    $ErrorActionPreference = 'Continue'
}

function Invoke-AiAnalysis {
    $dir = Get-LatestReportDir
    if (-not $dir) { Write-Host '还没有体检报告，请先执行体检。'; return }
    $key = Get-ApiKey
    if ($key -eq '') {
        Write-Host '尚未配置 DeepSeek API Key。请先选菜单 [7] 设置。'
        return
    }
    $reportFile = Join-Path $dir.FullName 'diagnosis.txt'
    $outFile = Join-Path $dir.FullName 'ai_analysis.txt'
    Write-Host ''
    Write-Host '正在准备上传报告；请审阅报告并在下一步确认。自动脱敏并不完整。'
    Write-Host ''
    & cscript //nologo (Join-Path $Root 'ai\ask_deepseek.vbs') $reportFile $outFile
    if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
        Write-Host ''
        Write-Host '================ AI 分析结果 ================'
        Write-Host (Get-Content $outFile -Encoding UTF8 | Out-String)
    }
}

function Show-Report {
    $dir = Get-LatestReportDir
    if (-not $dir) { Write-Host '还没有体检报告，请先执行体检。'; return }
    $html = Join-Path $dir.FullName 'diagnosis.html'
    $txt = Join-Path $dir.FullName 'diagnosis.txt'
    if (Test-Path $html) { Invoke-Item $html } else { Invoke-Item $txt }
    Write-Host ('报告位置: ' + $dir.FullName)
}

function Invoke-Fix {
    $dir = Get-LatestReportDir
    if (-not $dir) { Write-Host '还没有体检报告，请先执行体检。'; return }
    $ff = Join-Path $dir.FullName 'findings.ini'
    $lines = @()
    if (Test-Path $ff) { $lines = @(Get-Content $ff -Encoding UTF8 | Where-Object { $_.Trim() }) }
    if ($lines.Count -eq 0) {
        Write-Host '本次体检未发现可自动修复的问题。'
        Write-Host '可以选菜单 [3] 让 AI 进一步分析疑难问题。'
        return
    }
    Write-Host ''
    Write-Host '体检发现以下问题（可自动修复的）:'
    $i = 0
    $table = @()
    foreach ($l in $lines) {
        $parts = $l -split '\|', 5
        if ($parts.Count -lt 5) { continue }
        $i++
        $table += ,@($i, $parts[0], $parts[1], $parts[2], $parts[3])
        $fixName = '需人工/AI 判断'
        if ($parts[2]) { $fixName = $parts[2] }
        Write-Host ('  [' + $i + '] ' + $parts[0] + ' 严重度:' + $parts[1] + '  ' + $parts[3] + '  -> ' + $fixName)
    }
    Write-Host ''
    Write-Host '输入要修复的编号（如: 1,3），或输入 ALL 修复全部，直接回车返回:'
    $sel = Read-Host '选择'
    if ($sel -eq '') { return }
    $chosenIds = @()
    if ($sel -eq 'ALL') {
        foreach ($t in $table) { $chosenIds += $t[1] }
    } else {
        $nums = $sel -split '[,\s]+'
        foreach ($n in $nums) {
            if ($n -match '^\d+$') {
                $idx = [int]$n
                $row = $table | Where-Object { $_[0] -eq $idx } | Select-Object -First 1
                if ($row) { $chosenIds += $row[1] }
            }
        }
    }
    if ($chosenIds.Count -eq 0) { Write-Host '未选择任何问题。'; return }
    $fixIds = @()
    foreach ($l in $lines) {
        $parts = $l -split '\|', 5
        if ($chosenIds -contains $parts[0] -and $parts[2]) {
            if ($fixIds -notcontains $parts[2]) { $fixIds += $parts[2] }
        }
    }
    if ($fixIds.Count -eq 0) {
        Write-Host '所选问题没有对应的自动修复动作，建议选菜单 [3] 让 AI 给出处理方案。'
        return
    }
    Write-Host ''
    Write-Host ('将执行修复: ' + ($fixIds -join ', '))
    Write-Host '每个动作执行前都会再次确认，修改前自动备份到 backups\。'
    & (Join-Path $Root 'core\ps\fix.ps1') -Root $Root -Ids $fixIds -FindingIds $chosenIds
    $ErrorActionPreference = 'Continue'
}

function Invoke-Offline {
    $key = Get-ApiKey
    if ($key -eq '') { Write-Host '尚未配置 DeepSeek API Key。请先选菜单 [7] 设置。'; return }
    Write-Host ''
    Write-Host '开始批量分析 U 盘中的所有报告...'
    & cscript //nologo (Join-Path $Root 'ai\analyze.vbs')
    $sum = Join-Path $Root 'reports\analyze_summary.txt'
    if (Test-Path $sum) {
        Write-Host ''
        Write-Host (Get-Content $sum -Encoding UTF8 | Out-String)
    }
}

function Show-Help {
    $h = Join-Path $Root '使用说明.txt'
    if (Test-Path $h) { Invoke-Item $h } else { Write-Host '未找到使用说明.txt' }
}

$Host.UI.RawUI.WindowTitle = 'Pi Agent 维修助手'

# ===== 静态横幅（老系统/无 AI 模式；不播放动画）=====
try { & (Join-Path $ScriptDir 'intro.ps1') -Root $Root -NoAnim } catch { }

while ($true) {
    Clear-Host
    $key = Get-ApiKey
    $keyState = '未配置'
    if ($key -ne '') { $keyState = '已配置' }
    $dir = Get-LatestReportDir
    $latest = '无'
    if ($dir) { $latest = $dir.Name }
    Write-Host '==============================================='
    Write-Host '   Pi Agent 维修助手'
    Write-Host '   U盘系统诊断与修复工具  (支持 Win7/10/11)'
    Write-Host '==============================================='
    Write-Host ('   最近报告 : ' + $latest)
    Write-Host ('   API Key  : ' + $keyState)
    Write-Host '-----------------------------------------------'
    Write-Host '   [1] 快速体检 (约1分钟)'
    Write-Host '   [2] 完整体检 (含系统文件扫描, 5~15分钟)'
    Write-Host '   [3] AI 智能分析本次报告 (DeepSeek)'
    Write-Host '   [4] 查看本次报告'
    Write-Host '   [5] 执行修复 (先体检)'
    Write-Host '   [6] 离线批量分析 U盘内所有报告'
    Write-Host '   [7] 设置 API Key'
    Write-Host '   [8] 使用说明'
    Write-Host '   [0] 退出'
    Write-Host '==============================================='
    $choice = Read-Host '请选择'
    switch ($choice) {
        '1' { Invoke-Collect $true }
        '2' { Invoke-Collect $false }
        '3' { Invoke-AiAnalysis }
        '4' { Show-Report }
        '5' { Invoke-Fix }
        '6' { Invoke-Offline }
        '7' { Set-ApiKey }
        '8' { Show-Help }
        '0' { exit 0 }
        default { }
    }
    Write-Host ''
    Read-Host '按回车键返回菜单' | Out-Null
}

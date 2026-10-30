# ============================================================
# Pi Agent - 维修工单生成 (ticket.ps1)
# 数据来源：reports\<最新>\diagnosis.txt + findings.ini + ai_analysis.txt
#           + logs\actions.log（最近 12 小时实际执行的修复动作）
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File core\ps\ticket.ps1
#   可加参数：-Location "3号教学楼402" -Reporter "张老师" -Handler "我" -Note "备注"
# ============================================================
param(
    [string]$Root = '',
    [string]$Location = '',
    [string]$Reporter = '',
    [string]$Handler = '',
    [string]$Note = '',
    [string]$TicketName = '',
    [switch]$Quiet
)
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Root) { $Root = (Get-Item (Join-Path $ScriptDir '..\..')).FullName }

# ---------- 1) 找最新报告 ----------
$reportsDir = Join-Path $Root 'reports'
$latest = $null
if (Test-Path $reportsDir) {
    $dirs = @(Get-ChildItem $reportsDir | Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending)
    if ($dirs.Count -gt 0) { $latest = $dirs[0] }
}
if (-not $latest) {
    Write-Host '找不到体检报告（reports\ 为空）。请先做一次体检，再生成工单。'
    exit 1
}

# ---------- 2) 解析报告头 ----------
$genTime = ''
$osText = ''
$modeText = ''
$diagPath = Join-Path $latest.FullName 'diagnosis.txt'
if (Test-Path $diagPath) {
    foreach ($l in @(Get-Content $diagPath -Encoding UTF8 -TotalCount 30 -ErrorAction SilentlyContinue)) {
        if ($l -match '^生成时间\s*[:：]\s*(.+)$') { $genTime = $Matches[1].Trim() }
        elseif ($l -match '^操作系统\s*[:：]\s*(.+)$') { $osText = $Matches[1].Trim() }
        elseif ($l -match '^模式\s*[:：]\s*(.+)$') { $modeText = $Matches[1].Trim() }
    }
}
$machine = $latest.Name -replace '^\d{8}_\d{6}_', ''

# ---------- 3) 规则发现 ----------
$findings = @()
$ff = Join-Path $latest.FullName 'findings.ini'
if (Test-Path $ff) { $findings = @(Get-Content $ff -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }) }

# ---------- 4) AI 结论摘要 ----------
$aiText = ''
$aiPath = Join-Path $latest.FullName 'ai_analysis.txt'
if (Test-Path $aiPath) { $aiText = ([IO.File]::ReadAllText($aiPath, [Text.Encoding]::UTF8)).Trim() }
$aiSummary = ''
if ($aiText) {
    $keys = @('建议优先处理', '优先处理', '处理建议')
    $idx = -1
    foreach ($k in $keys) { $i2 = $aiText.LastIndexOf($k); if ($i2 -ge 0) { $idx = $i2; break } }
    if ($idx -ge 0) {
        $aiSummary = $aiText.Substring($idx, [Math]::Min(1200, $aiText.Length - $idx))
        if ($aiSummary.Length -lt 60) { $aiSummary = $aiText.Substring(0, [Math]::Min(900, $aiText.Length)) }
    } else { $aiSummary = $aiText.Substring(0, [Math]::Min(900, $aiText.Length)) }
    # 去掉 Markdown 装饰，便于粘贴到报修系统
    $aiSummary = $aiSummary -replace '(?m)^#{1,6}\s*', '' -replace '\*\*', '' -replace '(?m)^>\s?', ''
}

# ---------- 5) 本次实际执行的修复动作 ----------
$actions = @()
$logPath = Join-Path $Root 'logs\actions.log'
if (Test-Path $logPath) {
    $cut = (Get-Date).AddHours(-12)
    foreach ($l in @(Get-Content $logPath -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })) {
        if ($l -match '^(\d{14})\|') {
            try {
                $t = [datetime]::ParseExact($Matches[1], 'yyyyMMddHHmmss', $null)
                if ($t -ge $cut) { $actions += $l }
            } catch { }
        }
    }
}

# ---------- 6) 补录信息 ----------
$canPrompt = $true
try { if ([Console]::IsInputRedirected) { $canPrompt = $false } } catch { }
if ((-not $Quiet) -and $canPrompt) {
    Write-Host ''
    Write-Host ('将依据报告生成工单：' + $latest.Name)
    if (-not $TicketName) { $TicketName = Read-Host '工单名称（如：3号教学楼402打印机 / 张老师办公机；可留空用默认名）' }
    if (-not $Location) { $Location = Read-Host '位置（如：3号教学楼402办公室，可留空）' }
    if (-not $Reporter) { $Reporter = Read-Host '报修人（可留空）' }
    if (-not $Handler) { $Handler = Read-Host '处理人（可留空）' }
    if (-not $Note) { $Note = Read-Host '备注（可留空）' }
} elseif (-not $TicketName) {
    $TicketName = $machine + '-' + (Get-Date -Format 'MMdd-HHmm')
    Write-Host ('未在交互环境运行，已自动命名工单：' + $TicketName)
}
# ---------- 7) 组装工单 ----------
$sb = New-Object System.Text.StringBuilder
$nl = "`r`n"
[void]$sb.AppendLine('================ Pi Agent 维修工单 ================')
[void]$sb.AppendLine('工单号   : ' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $machine)
[void]$sb.AppendLine('工单名称 : ' + $(if ($TicketName) { $TicketName } else { '（未命名）' }))
[void]$sb.AppendLine('生成时间 : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('位置     : ' + $Location)
[void]$sb.AppendLine('报修人   : ' + $Reporter)
[void]$sb.AppendLine('处理人   : ' + $Handler)
[void]$sb.AppendLine('-----------------------------------------------')
[void]$sb.AppendLine('机器名   : ' + $machine)
[void]$sb.AppendLine('操作系统 : ' + $osText)
[void]$sb.AppendLine('体检时间 : ' + $genTime + '    体检模式: ' + $modeText)
[void]$sb.AppendLine('报告目录 : ' + $latest.FullName)
[void]$sb.AppendLine('-----------------------------------------------')
[void]$sb.AppendLine('一、自动规则发现（' + $findings.Count + ' 项）')
if ($findings.Count -eq 0) {
    [void]$sb.AppendLine('  （本地规则未发现已知问题）')
} else {
    foreach ($fl in $findings) {
        $p = $fl -split '\|', 5
        if ($p.Count -ge 5) {
            $fix = '人工/AI 判断'
            if ($p[2]) { $fix = $p[2] }
            [void]$sb.AppendLine('  [' + $p[0] + '] 严重度:' + $p[1] + '  ' + $p[3] + '  → ' + $fix)
            [void]$sb.AppendLine('        ' + $p[4])
        } else { [void]$sb.AppendLine('  ' + $fl) }
    }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('二、AI 分析结论')
if ($aiSummary) { [void]$sb.AppendLine($aiSummary) } else { [void]$sb.AppendLine('  （本次未做 AI 分析，可执行"校园网/打印机"模板或让助手分析报告后再生成工单）') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('三、本次实际执行的修复动作（来自 logs\actions.log，最近 12 小时）')
if ($actions.Count -eq 0) { [void]$sb.AppendLine('  （未执行修复，仅做诊断）') }
else { foreach ($a in $actions) { [void]$sb.AppendLine('  ' + $a) } }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('四、备注')
if ($Note) { [void]$sb.AppendLine('  ' + $Note) } else { [void]$sb.AppendLine('  （无）') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('五、后续待办（由处理人勾选/补充）')
[void]$sb.AppendLine('  [ ] 需要重启后复验')
[void]$sb.AppendLine('  [ ] 需要更换耗材/配件')
[void]$sb.AppendLine('  [ ] 需要网络管理员或打印服务器侧配合')
[void]$sb.AppendLine('  [ ] 需要重装系统/驱动')
[void]$sb.AppendLine('  [ ] 需要跟进回访')
[void]$sb.AppendLine('================================================')

$text = $sb.ToString()
$safeName = ($TicketName -replace '[\\/:*?"<>|]', '_').Trim()
if ($safeName.Length -gt 40) { $safeName = $safeName.Substring(0, 40) }
if ($safeName) { $outFile = Join-Path $latest.FullName ('工单_' + $safeName + '.txt') }
else { $outFile = Join-Path $latest.FullName '工单.txt' }
[IO.File]::WriteAllText($outFile, $text, (New-Object Text.UTF8Encoding $true))

Write-Host ''
Write-Host $text
Write-Host ('工单已保存: ' + $outFile)

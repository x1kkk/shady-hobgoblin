<#
    archive_records.ps1  v0.2
    Pi 维修助手 —— 维修记录归档（工单 + AI 分析 + 解决办法 → 本地 Git 仓库 → 私有远端）

    用法：
      .\archive_records.ps1 -Latest                    归档最近一次维修记录（出工单后自动调用）
      .\archive_records.ps1 -All                       归档所有未归档记录
      .\archive_records.ps1 -All -DryRun               仅预览，不做任何改动
      .\archive_records.ps1 -WeeklyCleanup             每周清理：删除已归档且超期的报告
      .\archive_records.ps1 -DetectDrive -WeeklyCleanup  自动探测 U 盘后清理（计划任务用）

    参数：
      -Root <dir>        Pi 根目录（默认脚本上级目录）
      -RepoDir <dir>     本地仓库工作副本（默认 %USERPROFILE%\repair-records）
      -RemoteUrl <url>   远端地址（可选；仓库已配置 origin 时一般不需要）
      -Token            已禁用；请通过 Git Credential Manager 或 SSH 自行认证
      -KeepDays <n>      清理保留天数（默认 7）
      -NoPush            只提交不推送
      -NoCleanup         归档后不触发清理
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$RepoDir = (Join-Path $env:USERPROFILE 'repair-records'),
    [string]$RemoteUrl,
    [string]$Token,
    [int]$KeepDays = 7,
    [switch]$Latest,
    [switch]$All,
    [switch]$WeeklyCleanup,
    [switch]$DetectDrive,
    [switch]$DryRun,
    [switch]$NoPush,
    [switch]$NoCleanup,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
# Remote access is opt-in; never embed credentials in a URL or print Git service output.
if ($Token) { throw 'Token arguments are disabled. Configure Git Credential Manager or SSH outside this tool.' }
if ($RemoteUrl -and $RemoteUrl -notmatch '^https://[^/@?#\s]+/[^@?#\s]+$' -and $RemoteUrl -notmatch '^git@[a-zA-Z0-9.-]+:[^\s@?#]+$') { throw 'Use a credential-free HTTPS or SSH repository URL.' }
if (-not $Root) { $Root = (Get-Item (Join-Path $PSScriptRoot '..')).FullName }
$Root = (Get-Item $Root).FullName
$configPath = Join-Path $Root 'archive.local.json'
if (-not (Test-Path -LiteralPath $configPath)) { Write-Host 'Archive disabled. Run setup_archive.ps1 with your own private repository configuration.'; exit 0 }
try { $archiveConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } catch { throw 'Invalid archive.local.json.' }
if ($archiveConfig.enabled -ne $true) { Write-Host 'Archive disabled by configuration.'; exit 0 }
if (-not $PSBoundParameters.ContainsKey('RepoDir') -and $archiveConfig.repoDir) { $RepoDir = [string]$archiveConfig.repoDir }
if ($archiveConfig.allowRemote -ne $true) { $NoPush = $true; if ($RemoteUrl) { throw 'Remote access has not been enabled.' } }
$repoFull = [IO.Path]::GetFullPath($RepoDir).TrimEnd('\')
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if ($repoFull -eq $rootFull -or $repoFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $rootFull.StartsWith($repoFull + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive must be outside the project tree.' }
if (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.repair-archive-private'))) { throw 'Not an explicitly initialized private archive.' }
$LogDir = Join-Path $Root 'logs'
if (-not $DryRun -and -not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir 'archive.log'
$script:pushOk = $false
$script:pushFail = $false
$Utf8Bom = New-Object Text.UTF8Encoding $true

function Log([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' | ' + $m
    Write-Host $line
    if (-not $DryRun) { try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { } }
}

function Write-TextFile([string]$path, [string]$text) {
    $d = Split-Path -Parent $path
    if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText($path, $text, $Utf8Bom)
}

# ---------- 盘符探测（计划任务用：找出当前插着的 Pi 盘）----------
function Find-PiDrive {
    $found = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if (-not $d.Root) { continue }
        if ((Test-Path (Join-Path $d.Root 'runtime\pi\pi.cmd')) -and (Test-Path (Join-Path $d.Root 'menu\pi_menu.ps1'))) {
            $found += $d.Root
        }
    }
    return $found
}

# ---------- Git 封装（始终带 -C 指向仓库）----------
function Invoke-Git([string[]]$gitArgs, [string]$workDir) {
    $full = @('-C', $workDir) + $gitArgs
    $out = & git @full 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -ne 0) { $out = 'Git operation failed; service output withheld to protect credentials.' }
    return [pscustomobject]@{ Code = $code; Out = $out.Trim() }
}

function Test-GitRepo([string]$dir) {
    if (-not (Test-Path (Join-Path $dir '.git'))) { return $false }
    $r = Invoke-Git @('rev-parse', '--is-inside-work-tree') $dir
    return ($r.Code -eq 0 -and $r.Out -eq 'true')
}
# ---------- 多机协作：与远端同步 + 带重试推送 ----------
function Sync-FromRemote([string]$dir) {
    $rem = Invoke-Git @('remote') $dir
    if ($rem.Code -ne 0 -or -not $rem.Out) { return }
    $ls = Invoke-Git @('ls-remote', '--heads', 'origin', 'main') $dir
    if ($ls.Code -ne 0 -or -not $ls.Out) { return }
    $pull = Invoke-Git @('pull', '--rebase', '--autostash', 'origin', 'main') $dir
    if ($pull.Code -eq 0) { Log '  已与远端同步（pull --rebase）' }
    else { Log ('  [warn] 与远端同步失败（继续按本地提交，推送时会再试）: ' + $pull.Out) }
}

function Push-WithRetry([string]$dir, [int]$maxTry = 3) {
    for ($i = 1; $i -le $maxTry; $i++) {
        $rem = Invoke-Git @('remote') $dir
        if ($rem.Code -ne 0 -or -not $rem.Out) { return $false }
        $ls = Invoke-Git @('ls-remote', '--heads', 'origin', 'main') $dir
        if ($ls.Code -eq 0 -and $ls.Out) {
            Invoke-Git @('pull', '--rebase', '--autostash', 'origin', 'main') $dir | Out-Null
        }
        $push = Invoke-Git @('push', '-u', 'origin', 'HEAD') $dir
        if ($push.Code -eq 0) { return $true }
        if ($i -lt $maxTry) {
            Log ('  推送被拒，正在重试（第 ' + $i + ' 次，' + (2 * $i) + 's 后）…')
            Start-Sleep -Seconds (2 * $i)
        }
    }
    return $false
}

# ---------- 工单字段解析（严格单行，避免跨行串字段）----------
function Get-TicketField([string]$text, [string[]]$names) {
    foreach ($n in $names) {
        $m = [regex]::Match($text, '(?m)^[ \t]*' + [regex]::Escape($n) + '[ \t]*[：:][ \t]*([^\r\n]*)$')
        if ($m.Success -and $m.Groups[1].Value.Trim()) { return $m.Groups[1].Value.Trim() }
    }
    return ''
}

# ---------- 记录识别 ----------
function Get-RecordInfo([string]$reportDir) {
    $id = Split-Path $reportDir -Leaf
    $tickets = @(Get-ChildItem $reportDir -Filter '工单*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $ais = @(Get-ChildItem $reportDir -Filter 'ai_analysis*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($tickets.Count -eq 0 -and $ais.Count -eq 0) { return $null }

    $read = {
        param($f)
        if (-not $f) { return '' }
        try { $t = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) } catch { $t = '' }
        if (-not $t) { try { $t = [IO.File]::ReadAllText($f, [Text.Encoding]::Default) } catch { } }
        return $t
    }
    $ticketText = ''
    if ($tickets.Count -gt 0) { $ticketText = (& $read $tickets[0].FullName) }
    $aiText = ''
    if ($ais.Count -gt 0) { $aiText = (& $read $ais[0].FullName) }
    # 统一行尾为 LF：否则 (?m)$ 无法匹配 CRLF 行末（工单文件为 CRLF）
    $ticketText = ($ticketText -replace "`r`n", "`n")
    $aiText = ($aiText -replace "`r`n", "`n")

    $machine = Get-TicketField $ticketText @('机器名', '计算机名')
    if (-not $machine) {
        $mv = [regex]::Match($id, '^\d{8}_\d{6}_(.+)$')
        if ($mv.Success) { $machine = $mv.Groups[1].Value }
    }
    $ticketName = Get-TicketField $ticketText @('工单名称')
    $location = Get-TicketField $ticketText @('位置', '故障位置')
    $reporter = Get-TicketField $ticketText @('报修人')
    $handler = Get-TicketField $ticketText @('处理人')
    $result = Get-TicketField $ticketText @('处理结果', '结果', '结论')

    # 解决办法：工单中的处置段落 → 当日 actions.log
    $solution = ''
    $ms = [regex]::Match($ticketText, '(?ms)^[ \t]*(?:三、)?[ \t]*(?:建议处置|处置|处理过程|解决办法)[^\r\n]*\r?\n(.*?)(?=\r?\n[ \t]*[一二三四五六七八九十]+、|\z)')
    if ($ms.Success) { $solution = $ms.Groups[1].Value.Trim() }
    if (-not $solution) {
        $day = ''
        $md = [regex]::Match($id, '^(\d{8})')
        if ($md.Success) { $day = $md.Groups[1].Value }
        $act = Join-Path $Root 'logs\actions.log'
        if ($day -and (Test-Path $act)) {
            $prefix = $day.Substring(0, 4) + '-' + $day.Substring(4, 2) + '-' + $day.Substring(6, 2)
            $lines = @(Get-Content $act -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match [regex]::Escape($prefix) })
            if ($lines.Count -gt 0) { $solution = '（依据当日修复动作日志）' + "`r`n" + (($lines | Select-Object -Last 25) -join "`r`n") }
        }
    }

    $when = $null
    $mt = [regex]::Match($id, '^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})')
    if ($mt.Success) {
        try {
            $when = [datetime]::new([int]$mt.Groups[1].Value, [int]$mt.Groups[2].Value, [int]$mt.Groups[3].Value,
                                    [int]$mt.Groups[4].Value, [int]$mt.Groups[5].Value, [int]$mt.Groups[6].Value)
        } catch { }
    }
    if (-not $when) { $when = (Get-Item $reportDir).LastWriteTime }

    return [pscustomobject]@{
        Id = $id; Dir = $reportDir; When = $when; Machine = $machine
        TicketName = $ticketName; Location = $location; Reporter = $reporter
        Handler = $handler; Result = $result
        TicketText = $ticketText; AiText = $aiText; Solution = $solution
        HasTicket = ($tickets.Count -gt 0); HasAi = ($ais.Count -gt 0)
    }
}

function Get-Records([string]$reportsRoot) {
    if (-not (Test-Path $reportsRoot)) { return @() }
    $out = @()
    foreach ($d in @(Get-ChildItem $reportsRoot -Directory -ErrorAction SilentlyContinue)) {
        $r = Get-RecordInfo $d.FullName
        if ($r) { $out += $r }
    }
    return @($out | Sort-Object When)
}

function Get-RecordTargetPath([string]$repoDir, $rec) {
    return (Join-Path $repoDir ('records\' + $rec.When.ToString('yyyy-MM') + '\' + $rec.Id))
}

# ---------- 归档单条 ----------
function Archive-Record($rec, [string]$repoDir, [switch]$NoPushMode) {
    $target = Get-RecordTargetPath $repoDir $rec
    $relTarget = $target.Substring($repoDir.Length).TrimStart('\')

    if (Test-Path $target) { Log ('  - 跳过（已归档）: ' + $rec.Id); return 'skipped' }
    if ($DryRun) {
        Log ('  * 将归档: ' + $rec.Id + '  [工单=' + $rec.HasTicket + ' AI=' + $rec.HasAi + ' 解决办法=' + [bool]$rec.Solution + '] → ' + $relTarget)
        return 'preview'
    }

    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Log ('    [1/3] 生成记录文件（ticket.md / ai_analysis.md / solution.md / meta.json）')

    $hdr = '# 维修工单 ' + $rec.Id + "`r`n`r`n| 项 | 值 |`r`n|---|---|`r`n"
    $hdr += '| 时间 | ' + $rec.When.ToString('yyyy-MM-dd HH:mm:ss') + " |`r`n"
    $hdr += '| 机器名 | ' + $rec.Machine + " |`r`n"
    if ($rec.TicketName) { $hdr += '| 工单名称 | ' + $rec.TicketName + " |`r`n" }
    if ($rec.Location) { $hdr += '| 位置 | ' + $rec.Location + " |`r`n" }
    if ($rec.Reporter) { $hdr += '| 报修人 | ' + $rec.Reporter + " |`r`n" }
    if ($rec.Handler) { $hdr += '| 处理人 | ' + $rec.Handler + " |`r`n" }
    if ($rec.Result) { $hdr += '| 处理结果 | ' + $rec.Result + " |`r`n" }
    $hdr += "`r`n## 原始工单`r`n`r`n"
    $ticketBody = if ($rec.TicketText) { $rec.TicketText.Trim() } else { '（本次未生成工单文本）' }
    Write-TextFile (Join-Path $target 'ticket.md') ($hdr + '```text' + "`r`n" + $ticketBody + "`r`n" + '```' + "`r`n")

    Write-TextFile (Join-Path $target 'ai_analysis.md') ('# AI 分析 ' + $rec.Id + "`r`n`r`n" + $(if ($rec.AiText) { $rec.AiText.Trim() } else { '（本次无 ai_analysis.txt）' }) + "`r`n")

    Write-TextFile (Join-Path $target 'solution.md') ('# 解决办法 ' + $rec.Id + "`r`n`r`n" + $(if ($rec.Solution) { $rec.Solution } else { '（工单未记录处置内容，可在处理完成后补充）' }) + "`r`n")

    $meta = [ordered]@{
        id = $rec.Id
        time = $rec.When.ToString('yyyy-MM-dd HH:mm:ss')
        machine = $rec.Machine
        ticketName = $rec.TicketName
        location = $rec.Location
        reporter = $rec.Reporter
        handler = $rec.Handler
        result = $rec.Result
        hasTicket = $rec.HasTicket
        hasAi = $rec.HasAi
        hasSolution = [bool]$rec.Solution
        archivedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    Write-TextFile (Join-Path $target 'meta.json') (($meta | ConvertTo-Json -Depth 5) + "`r`n")
    Log ('  + 已归档: ' + $rec.Id + ' → ' + $relTarget)

    $add = Invoke-Git @('add', '--', $relTarget) $repoDir
    if ($add.Code -ne 0) { Log ('  [warn] git add 失败: ' + $add.Out); return 'failed' }
    $msg = '记录 ' + $rec.Id + ' | ' + $rec.Machine + $(if ($rec.Result) { ' | ' + $rec.Result } else { '' })
    $staged = Invoke-Git @('diff', '--cached', '--quiet') $repoDir
    if ($staged.Code -eq 0) {
        Log ('    [2/3] 无变更（仓库已有相同内容），跳过提交: ' + $rec.Id)
        return 'skipped'
    }
    $commit = Invoke-Git @('commit', '-m', $msg) $repoDir
    if ($commit.Code -ne 0) { Log ('  [warn] git commit 失败: ' + $commit.Out); return 'failed' }
    Log ('    [2/3] 本地提交: ' + $msg)

    if (-not $NoPushMode -and -not $NoPush) {
        $rem = Invoke-Git @('remote') $repoDir
        if ($rem.Code -eq 0 -and $rem.Out) {
            if (Push-WithRetry $repoDir) { $script:pushOk = $true; Log '    [3/3] 推送 → origin/main  ✓ 已上传 Gitee' } else { $script:pushFail = $true; Log '    [3/3] 推送失败（已本地提交，下次归档自动补推）' }
        } else { Log '  [warn] 未配置远端：请先运行 tools\setup_archive.ps1' }
    } elseif ($NoPush) { Log '  [info] -NoPush：仅本地提交' }
    return 'archived'
}

# ---------- 每周清理 ----------
function Invoke-WeeklyCleanup([string]$repoDir, [int]$keepDays) {
    $stamp = Join-Path $LogDir 'archive-last-cleanup.txt'
    if (Test-Path $stamp) {
        try {
            $dt = [datetime]::Parse((Get-Content $stamp -Raw).Trim())
            if (((Get-Date) - $dt).TotalDays -lt 6.0) {
                Log ('清理：上次 ' + $dt.ToString('yyyy-MM-dd HH:mm') + ' 已执行，未满 7 天，跳过')
                return
            }
        } catch { }
    }
    # 删除类操作硬性授权：交互模式需输入 DELETE；非交互（计划任务）必须 -Yes
    $authorized = [bool]$Yes
    if (-not $authorized -and -not $DryRun) {
        $interactive = $true
        try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { $interactive = $false }
        if ($interactive) {
            Write-Host ('即将删除 ' + '（已归档且超过 ' + $keepDays + ' 天）的报告目录。') -ForegroundColor Yellow
            $ans = Read-Host '输入 DELETE 确认删除（其他任意输入取消）'
            $authorized = ($ans -eq 'DELETE' -or $ans -eq 'delete')
        } else {
            Log '  [拒绝] 删除类操作需要 -Yes 授权（计划任务请带 -Yes）；本次跳过清理'
        }
    }
    if (-not $authorized) {
        Log '未获得删除授权：清理已跳过，所有报告保留。'
        return
    }

    $limit = (Get-Date).AddDays(-1 * $keepDays)
    $candidates = @()
    foreach ($rec in (Get-Records (Join-Path $Root 'reports'))) {
        if ($rec.When -lt $limit) {
            if (Test-Path (Get-RecordTargetPath $repoDir $rec)) { $candidates += $rec }
        }
    }
    Log ('清理：候选 ' + $candidates.Count + ' 条（已归档且超过 ' + $keepDays + ' 天）')
    foreach ($c in $candidates) {
        if ($DryRun) { Log ('  * 将删除: ' + $c.Id) }
        else {
            try { Remove-Item $c.Dir -Recurse -Force -ErrorAction Stop; Log ('  - 已删除本地报告: ' + $c.Id) }
            catch { Log ('  [warn] 删除失败: ' + $c.Id + ' : ' + $_.Exception.Message) }
        }
    }
    if (-not $DryRun) {
        Write-TextFile $stamp ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n")
        Log '清理完成（已记录时间戳）'
    }
}

# ====================== 主流程 ======================
$script:sw = [Diagnostics.Stopwatch]::StartNew()
Log '===== 归档任务开始 ====='
if ($DetectDrive) {
    $drives = @(Find-PiDrive)
    Log ('  探测 Pi 盘: ' + (($drives | ForEach-Object { $_ }) -join ', '))
    if ($drives.Count -eq 0) { Log '  未探测到 Pi 盘（U 盘未插入），结束'; Log '===== 归档任务结束 ====='; exit 0 }
    foreach ($dv in $drives) {
        Log ('--- 处理盘 ' + $dv + ' ---')
        $childArgs = @('-Root', $dv, '-RepoDir', $RepoDir, '-KeepDays', [string]$KeepDays)
        if ($WeeklyCleanup) { $childArgs += '-WeeklyCleanup' }
        if ($NoPush) { $childArgs += '-NoPush' }
        if ($Yes) { $childArgs += '-Yes' }
        if ($DryRun) { $childArgs += '-DryRun' }
        & $PSCommandPath @childArgs
    }
    Log '===== 归档任务结束 ====='
    exit 0
}

Log ('  Root=' + $Root + '  Repo=' + $RepoDir + '  模式=' + $(if ($Latest) { 'Latest' } elseif ($All) { 'All' } else { 'none' }) + $(if ($WeeklyCleanup) { '+Cleanup' } else { '' }) + $(if ($DryRun) { ' [DryRun]' } else { '' }))

$repoOk = Test-GitRepo $RepoDir
if (-not $repoOk) {
    Log ('  [warn] 仓库未初始化: ' + $RepoDir + '  →  先运行 tools\setup_archive.ps1')
    if (-not $DryRun) { exit 3 }
}

if ($repoOk) {
    $existingRemote = Invoke-Git @('remote', 'get-url', 'origin') $RepoDir
    if ($existingRemote.Code -eq 0 -and ($existingRemote.Out -match '^https?://[^/]*@' -or $existingRemote.Out -match '[?#]')) { throw 'Existing origin may contain credentials. Replace it with a clean URL outside this tool.' }
}
if ($RemoteUrl -and $repoOk -and -not $DryRun) {
    $url = $RemoteUrl
    Invoke-Git @('remote', 'remove', 'origin') $RepoDir | Out-Null
    Invoke-Git @('remote', 'add', 'origin', $url) $RepoDir | Out-Null
    Log '  远端已设置（地址不写入日志）'
}

if (-not $DryRun -and -not $NoPush -and $repoOk) { Sync-FromRemote $RepoDir }
$records = @(Get-Records (Join-Path $Root 'reports'))
Log ('  发现记录: ' + $records.Count + ' 条')
$ordered = $records
if ($Latest) { $ordered = @($records | Select-Object -Last 1) }

$archived = 0; $skipped = 0; $preview = 0; $failed = 0
foreach ($rec in $ordered) {
    $r = Archive-Record $rec $RepoDir -NoPushMode:($NoPush)
    if ($r -eq 'archived') { $archived++ }
    elseif ($r -eq 'skipped') { $skipped++ }
    elseif ($r -eq 'preview') { $preview++ }
    elseif ($r -eq 'failed') { $failed++ }
}
Log ('  归档=' + $archived + ' 跳过=' + $skipped + ' 预览=' + $preview + ' 失败=' + $failed)

if ($WeeklyCleanup -and -not $NoCleanup) { Invoke-WeeklyCleanup $RepoDir $KeepDays }

# 补推：离线期间累积的本地提交
if (-not $DryRun -and -not $NoPush -and $repoOk) {
    $rem = Invoke-Git @('remote') $RepoDir
    if ($rem.Code -eq 0 -and $rem.Out) {
        $ahead = Invoke-Git @('rev-list', '--count', 'origin/main..HEAD') $RepoDir
        if ($ahead.Code -eq 0 -and $ahead.Out -match '^\d+$' -and [int]$ahead.Out -gt 0) {
            Log ('  发现 ' + $ahead.Out + ' 个未推送提交，正在补推…')
            if (Push-WithRetry $RepoDir) { $script:pushOk = $true; Log '  ↑ 补推完成（历史提交已同步）' } else { $script:pushFail = $true; Log '  [warn] 补推失败，稍后重试' }
        }
    }
}
# ---------- 结果汇总（供菜单/界面显示）----------
$pushedText = if ($archived -eq 0 -and -not $script:pushOk -and -not $DryRun) { '无新记录（未变更）' } elseif ($script:pushOk -and -not $script:pushFail) { '已上传 Gitee' } elseif ($script:pushFail) { '推送失败（已本地提交，稍后补推）' } else { '仅本地提交' }
$result = [ordered]@{
    time = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    root = $Root
    mode = $(if ($Latest) { 'Latest' } elseif ($All) { 'All' } else { 'none' })
    found = $records.Count
    archived = $archived
    skipped = $skipped
    failed = $failed
    pushed = ($script:pushOk -and -not $script:pushFail)
    pushText = $pushedText
    dryRun = [bool]$DryRun
}
if (-not $DryRun) { try { Write-TextFile (Join-Path $LogDir 'archive-last-result.json') (($result | ConvertTo-Json -Depth 4) + "`r`n") } catch { } }

$bar = '+--------------------------------------------------------------+'
Write-Host ''
Write-Host $bar -ForegroundColor DarkCyan
Write-Host '|  维修记录归档结果                                            |' -ForegroundColor Cyan
Write-Host $bar -ForegroundColor DarkCyan
Write-Host ('|  记录来源 : ' + $Root) -ForegroundColor Gray
Write-Host ('|  处理情况 : 发现 ' + $records.Count + ' 条 / 新归档 ' + $archived + ' 条 / 已有 ' + $skipped + ' 条 / 失败 ' + $failed) -ForegroundColor Gray
Write-Host ('|  上传状态 : ' + $pushedText) -ForegroundColor $(if ($result.pushed) { 'Green' } elseif ($script:pushFail) { 'Yellow' } else { 'Gray' })
Write-Host ('|  归档位置 : ' + $RepoDir + '\records\') -ForegroundColor Gray
Write-Host ('|  日志     : ' + $LogFile) -ForegroundColor DarkGray
Write-Host $bar -ForegroundColor DarkCyan
Write-Host ''
Log '===== 归档任务结束 ====='
exit 0

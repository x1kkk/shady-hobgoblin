<#
    setup_archive.ps1  v0.3
    初始化维修记录归档仓库（支持多台电脑协作：远端有历史则克隆，而不是 git init）

    用法：
      .\setup_archive.ps1 -RepoDir "$env:USERPROFILE\repair-records" -User 用户名 -Repo 仓库名 -AllowRemote
      .\setup_archive.ps1 -RepoDir "D:\repair-records" -RemoteUrl "https://gitee.com/example/private-records.git" -AllowRemote

    多机协作要点：
      - 远端已有提交 -> git clone（共享同一历史，避免 unrelated histories 推送被拒）
      - 远端为空      -> git init + 首次 push
      - 已存在仓库    -> fetch 远端最新（不覆盖本地提交）
#>
[CmdletBinding()]
param(
    [string]$RepoDir = (Join-Path $env:USERPROFILE 'repair-records'),
    [string]$RemoteUrl,
    [string]$User,
    [string]$Repo,
    [string]$Token,
    [switch]$AllowRemote
)

$ErrorActionPreference = 'Stop'
if ($Token) { throw 'Token arguments are disabled. Use Git Credential Manager or SSH.' }
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$resolvedRepo = [IO.Path]::GetFullPath($RepoDir).TrimEnd('\')
if ($resolvedRepo -eq $project -or $resolvedRepo.StartsWith($project + '\', [StringComparison]::OrdinalIgnoreCase) -or $project.StartsWith($resolvedRepo + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive repository must be separate from the source tree.' }
$ancestor = Split-Path -Parent $resolvedRepo
while ($ancestor) {
    if (Test-Path -LiteralPath (Join-Path $ancestor '.git')) { throw 'Archive repository cannot be nested in another Git worktree.' }
    $ancestor = Split-Path -Parent $ancestor
}
function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Say '[错误] 未找到 git，请先安装 Git for Windows（Pi 运行也需要它）' 'Red'
    exit 3
}
Say ('git: ' + ((& git --version 2>&1 | Out-String).Trim()))

New-Item -ItemType Directory -Force -Path $RepoDir | Out-Null
$RepoDir = (Get-Item $RepoDir).FullName
Say ('仓库目录: ' + $RepoDir)

# ---------- 远端地址（先算出来，init 阶段要用）----------
$url = $RemoteUrl
if (-not $url -and $User -and $Repo) { $url = 'https://gitee.com/' + $User + '/' + $Repo + '.git' }
if ($url -and -not $AllowRemote) { throw 'Remote setup requires -AllowRemote. Use a private repository you control.' }
if ($url -and $url -notmatch '^https://[^/@?#\s]+/[^@?#\s]+$' -and $url -notmatch '^git@[a-zA-Z0-9.-]+:[^\s@?#]+$') { throw 'Use a credential-free HTTPS or SSH repository URL.' }
if ($url -and (Read-Host 'Remote archiving uploads machine/user information. Type UPLOAD to opt in') -cne 'UPLOAD') { throw 'Cancelled.' }
$urlSafe = '(address withheld)'
if (Test-Path -LiteralPath (Join-Path $RepoDir '.git')) {
    $oldUrl = & git -C $RepoDir remote get-url origin 2>$null | Out-String
    if ($oldUrl -match '^https?://[^/]*@' -or $oldUrl -match '[?#]') { throw 'Existing origin may contain credentials. Replace it outside this tool.' }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.repair-archive-private'))) { throw 'Existing repository is not marked as a private repair archive.' }
}

# ---------- 仓库初始化：远端有历史则克隆 ----------
$gitDir = Join-Path $RepoDir '.git'
if (-not (Test-Path $gitDir)) {
    $remoteHasHistory = $false
    if ($url) {
        $ls = & git ls-remote --heads $url 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $ls.Trim()) { $remoteHasHistory = $true }
    }
    if ($remoteHasHistory) {
        Say '远端已有历史 -> 克隆（保证与其它电脑共享同一历史）...' 'Cyan'
        $clone = & git clone $url $RepoDir 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Say '[错误] 克隆失败；服务输出已隐藏以保护凭据。' 'Red'
            Say '请检查网络/令牌后重试。切勿改用 git init，否则会与远端历史分歧导致推送被拒。' 'Yellow'
            exit 5
        }
        Say '已克隆远端仓库（历史一致）' 'Green'
    } else {
        Push-Location $RepoDir
        try {
            & git init 2>&1 | Out-Null
            & git symbolic-ref HEAD refs/heads/main 2>&1 | Out-Null
            Say '已初始化 Git 仓库（分支 main；远端当前为空）' 'Green'
        } finally { Pop-Location }
    }
} else {
    Say '已存在 Git 仓库，跳过初始化' 'Yellow'
    if ($url) {
        $fetch = & git -C $RepoDir fetch origin 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Say '已 fetch 远端最新提交' 'Green' }
        else { Say '[warn] fetch 失败；服务输出已隐藏。' 'Yellow' }
    }
}

# ---------- 骨架文件（已存在则不覆盖）----------
$gitignoreLines = @(
    '# 归档仓库：只保存维修记录，忽略本地临时物'
    '*.tmp'
    '*.swp'
    '.DS_Store'
    'Thumbs.db'
    'desktop.ini'
)
$gitattributesLines = @('* text=auto eol=lf', '*.png binary', '*.jpg binary', '*.pdf binary')
$readmeLines = @(
    '# 维修记录归档（私有）'
    ''
    '本仓库由 Pi 维修助手的 `tools\archive_records.ps1` 自动维护，保存每次维修的：'
    ''
    '- `ticket.md` —— 工单（含机器名/位置/报修人/处理人/结果）'
    '- `ai_analysis.md` —— AI 分析结论'
    '- `solution.md` —— 实际解决办法（处置步骤 / 当日修复动作）'
    '- `meta.json` —— 结构化元数据'
    ''
    '目录按 `records/<年-月>/<时间戳_机器名>/` 组织。'
    ''
    '> 私有仓库，勿公开；提交信息格式：`记录 <ID> | <机器> | <结果>`。'
)
$enc = New-Object Text.UTF8Encoding $true
foreach ($pair in @(
    @('.gitignore', ($gitignoreLines -join "`r`n")),
    @('.gitattributes', ($gitattributesLines -join "`r`n")),
    @('README.md', ($readmeLines -join "`r`n"))
)) {
    $p = Join-Path $RepoDir $pair[0]
    if (-not (Test-Path $p)) { [IO.File]::WriteAllText($p, $pair[1] + "`r`n", $enc); Say ('  + ' + $pair[0]) }
}
New-Item -ItemType Directory -Force -Path (Join-Path $RepoDir 'records') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RepoDir 'index') | Out-Null

# ---------- 远端配置（已存在则 set-url，避免破坏克隆来的 origin）----------
if ($url) {
    $remotes = ((& git -C $RepoDir remote 2>&1) -join ' ').Trim()
    if ($remotes -match 'origin') {
        & git -C $RepoDir remote set-url origin $url 2>&1 | Out-Null
        Say ('远端已更新: ' + $urlSafe) 'Green'
    } else {
        & git -C $RepoDir remote add origin $url 2>&1 | Out-Null
        Say ('已配置远端: ' + $urlSafe) 'Green'
    }
} else {
    Say '未配置远端（可稍后执行：git -C "<仓库>" remote add origin <URL>）' 'Yellow'
}

# Local opt-in configuration is never part of a public build.
Set-Content -LiteralPath (Join-Path $RepoDir '.repair-archive-private') -Value 'Private repair records; never publish.' -Encoding UTF8
[ordered]@{ enabled=$true; repoDir=$RepoDir; allowRemote=[bool]$AllowRemote; autoArchive=$false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'archive.local.json') -Encoding UTF8

# ---------- 初始提交（仅当有未提交变更）----------
Push-Location $RepoDir
try {
    & git add -- .gitignore .gitattributes README.md .repair-archive-private 2>&1 | Out-Null
    $st = (& git status --porcelain 2>&1 | Out-String).Trim()
    if ($st) { & git commit --only -m '初始化归档仓库' -- .gitignore .gitattributes README.md .repair-archive-private 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Initial archive commit failed; check your own Git identity configuration.' }; Say '已创建初始提交' 'Green' }
    else { Say '工作区干净，无需提交' 'Yellow' }
    Say ''
    Say '===== 下一步 =====' 'Cyan'
    Say ('1) 首次全量归档：powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'archive_records.ps1') + '" -All')
    Say '2) 之后每次维修完成，菜单选 [12] 或由出工单/会话结束流程自动调用 -Latest'
    Say '3) 每周清理：计划任务执行 archive_records.ps1 -DetectDrive -WeeklyCleanup'
    Say '4) 多台电脑：每台都运行本脚本（会 clone 同一历史），归档时自动 pull --rebase + 重试推送'
} finally { Pop-Location }

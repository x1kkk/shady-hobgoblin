# ============================================================
# Pi Agent 开场动画 (intro.ps1)   字标：.Ekkk   文案：网络中心
# 随机样式：typewriter(打字机) / decrypt(乱码解密) / rain(数字雨)
# 共同结尾：网络中心 打字机出现 -> 闪烁几次 -> .EKKK 徽章 -> 载入提示
# 预览：
#   powershell -NoProfile -ExecutionPolicy Bypass -File menu\intro.ps1                # 随机
#   ... -Style decrypt / -Style rain / -Style typewriter                              # 指定
#   ... -Style list                                                                   # 列出样式
#   ... -Slow / -Fast / -NoAnim / -Trace / -Scale 1.5 / -Ascii
# config.ini：skip_intro / intro_charset / intro_speed / intro_scale / intro_skipkey
#             intro_style=random|typewriter|decrypt|rain    intro_styles=...    intro_blink=3
# ============================================================
param(
    [string]$Root = '',
    [switch]$NoAnim,
    [switch]$Slow,
    [switch]$Fast,
    [switch]$Force,
    [switch]$Ascii,
    [switch]$Trace,
    [double]$Scale = 0,
    [string]$Style = ''
)
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Root) { $Root = (Get-Item (Join-Path $ScriptDir '..')).FullName }

# ---------- 配置 ----------
$skipIntro = $false
$skipKey = $true
$charset = 'block'
$speed = 'normal'
$cfgScale = 0
$cfgStyle = 'random'
$cfgPool = 'typewriter,decrypt,rain'
$blinkTimes = 3
$cfg = Join-Path $Root 'config.ini'
if (Test-Path $cfg) {
    foreach ($l in @(Get-Content $cfg -ErrorAction SilentlyContinue)) {
        if ($l -match '^\s*skip_intro\s*=\s*1') { $skipIntro = $true }
        if ($l -match '^\s*intro_charset\s*=\s*ascii') { $charset = 'ascii' }
        if ($l -match '^\s*intro_speed\s*=\s*(\w+)') { $speed = $Matches[1].ToLower() }
        if ($l -match '^\s*intro_scale\s*=\s*([\d\.]+)') { $cfgScale = [double]$Matches[1] }
        if ($l -match '^\s*intro_skipkey\s*=\s*0') { $skipKey = $false }
        if ($l -match '^\s*intro_style\s*=\s*([\w]+)') { $cfgStyle = $Matches[1].ToLower() }
        if ($l -match '^\s*intro_styles\s*=\s*(.+)$') { $cfgPool = $Matches[1].Trim() }
        if ($l -match '^\s*intro_blink\s*=\s*(\d+)') { $blinkTimes = [int]$Matches[1] }
    }
}
if ($Ascii) { $charset = 'ascii' }
if ($Slow) { $speed = 'slow' }
if ($Fast) { $speed = 'fast' }
if (($Scale -le 0) -and ($cfgScale -gt 0)) { $Scale = $cfgScale }

# ---------- 样式选择 ----------
$allStyles = @('typewriter', 'decrypt', 'rain')
if ($Style -eq 'list') {
    Write-Host ''
    Write-Host '  可用的开场动画样式：' -ForegroundColor Cyan
    Write-Host '    typewriter   打字机：字形逐行浮现'
    Write-Host '    decrypt      乱码解密：随机字符逐列收敛成字形'
    Write-Host '    rain         数字雨：字符雨落下后字形浮现'
    Write-Host '    random       随机（默认，抽完会写进日志）' -ForegroundColor Gray
    Write-Host ''
    return
}
if ($skipIntro -and (-not $Force) -and (-not $NoAnim) -and (-not $Trace)) { return }

if ($Style -ne '') { $style = $Style.ToLower() } else { $style = $cfgStyle }
if (($style -eq 'random') -or ($style -eq '')) {
    $pool = @()
    foreach ($s in ($cfgPool -split ',')) { $t = $s.Trim().ToLower(); if (($t -ne '') -and ($allStyles -contains $t)) { $pool += $t } }
    if ($pool.Count -eq 0) { $pool = $allStyles }
    $style = [string](Get-Random -InputObject $pool)
}
if (-not ($allStyles -contains $style)) { $style = 'typewriter' }

$factor = 1.0
if ($speed -eq 'fast') { $factor = 0.5 }
if ($speed -eq 'slow') { $factor = 3.0 }
if ($charset -eq 'ascii') { $B = '#'; $L1 = '='; $L2 = '-' } else { $B = [string][char]0x2588; $L1 = [string][char]0x2550; $L2 = [string][char]0x2500 }

# ---------- 开场日志 ----------
function Write-IntroLog([string]$msg) {
    try {
        $logRoot = (Get-Item (Join-Path $ScriptDir '..')).FullName
        $logDir = Join-Path $logRoot 'logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        Add-Content -Path (Join-Path $logDir 'intro.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' | ' + $msg) -Encoding UTF8
    } catch { }
}

# ---------- 网格与笔画 ----------
function New-Grid([int]$gw, [int]$gh) {
    $g = New-Object 'object[]' $gh
    for ($gy = 0; $gy -lt $gh; $gy++) { $g[$gy] = (' ' * $gw).ToCharArray() }
    return , $g
}
function Fill-Rect($g, [int]$x, [int]$y, [int]$rw, [int]$rh) {
    for ($yy = $y; $yy -lt ($y + $rh); $yy++) {
        if ($yy -lt 0 -or $yy -ge $g.Count) { continue }
        for ($xx = $x; $xx -lt ($x + $rw); $xx++) {
            if ($xx -lt 0 -or $xx -ge $g[$yy].Count) { continue }
            $g[$yy][$xx] = '#'
        }
    }
}
function Draw-Diag($g, [int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$t) {
    $steps = [Math]::Abs($y2 - $y1)
    if ($steps -lt 1) { $steps = 1 }
    for ($s = 0; $s -le $steps; $s++) {
        $y = $y1 + [int](($y2 - $y1) * $s / $steps)
        $x = $x1 + [int](($x2 - $x1) * $s / $steps) - [int]($t / 2)
        Fill-Rect $g $x $y $t 1
    }
}
function New-GlyphE([int]$w, [int]$h, [int]$t) {
    $g = New-Grid $w $h
    Fill-Rect $g 0 0 $t $h
    Fill-Rect $g 0 0 $w $t
    Fill-Rect $g 0 ($h - $t) $w $t
    $mid = [int](($h - $t) / 2)
    Fill-Rect $g 0 $mid $w $t
    return , $g
}
function New-GlyphK([int]$w, [int]$h, [int]$t, [switch]$Lower) {
    $g = New-Grid $w $h
    Fill-Rect $g 0 0 $t $h
    if ($Lower) {
        $xh = [int]($h * 0.55)
        $y0 = $h - $xh
        $mid = $y0 + [int]($xh / 2)
    } else {
        $y0 = 0
        $mid = [int]($h / 2)
    }
    Draw-Diag $g ($w - $t) $y0 ($t - 1) $mid $t
    Draw-Diag $g ($t - 1) $mid ($w - $t) ($h - $t) $t
    return , $g
}

# ---------- 尺寸自适应 ----------
$winW = 120
$winH = 30
try { if ([Console]::WindowWidth -gt 20) { $winW = [Console]::WindowWidth } } catch { }
try { if ([Console]::WindowHeight -gt 10) { $winH = [Console]::WindowHeight } } catch { }
$cw = $winW - 2
$gapDot = 2
$gapL = 3
if ($Scale -eq 0) { $Scale = 1 }
$fitByWidth = [int]((($cw - 17) / 4.2) * $Scale)
$fitByHeight = [int]((($winH - 13) / 0.72) * $Scale)
$LW = [Math]::Min($fitByWidth, $fitByHeight)
if ($LW -lt 12) { $LW = 12 }
$LH = [int]($LW * 0.72)
if ($LH -lt 9) { $LH = 9 }
$T = [Math]::Max(2, [int]($LW / 8))
$dotH = [Math]::Max(2, $T)
$dotW = $dotH * 2

$E = New-GlyphE $LW $LH $T
$k1 = New-GlyphK $LW $LH $T -Lower
$k2 = New-GlyphK $LW $LH $T -Lower
$k3 = New-GlyphK $LW $LH $T -Lower
$rows = @()
for ($y = 0; $y -lt $LH; $y++) {
    $prefix = ' ' * $dotW
    if ($y -ge ($LH - $dotH)) { $prefix = '#' * $dotW }
    $rows += ($prefix + (' ' * $gapDot) + (-join $E[$y]) + (' ' * $gapL) + (-join $k1[$y]) + (' ' * $gapL) + (-join $k2[$y]) + (' ' * $gapL) + (-join $k3[$y]))
}
if ($charset -ne 'ascii') {
    $blockW = 1
    try {
        $px = [Console]::CursorLeft
        Write-Host $B -NoNewline
        $blockW = [Console]::CursorLeft - $px
        if ($blockW -le 0) { $blockW = 1 }
    } catch { $blockW = 1 }
    if ($blockW -ne 1) { $charset = 'ascii'; $B = '#'; $L1 = '='; $L2 = '-' }
}
$logo = @()
foreach ($r in $rows) { $logo += $r.Replace('#', $B) }
$logoW = 0
foreach ($r in $logo) { if ($r.Length -gt $logoW) { $logoW = $r.Length } }
$logoH = $logo.Count
$dx = [Math]::Max(1, [int]($LW / 12))
$dy = [Math]::Max(1, [int]($LH / 14))
$shadowColor = 'DarkGray'
$shadowChar = $B
if ($charset -eq 'ascii') { $shadowChar = '.' }
$totalW = $logoW + $dx
$totalH = $logoH + $dy
$sub = '网 络 中 心'
$badge = ' .EKKK '
$palette = @('DarkCyan', 'DarkCyan', 'Cyan', 'Cyan', 'Cyan', 'White', 'White', 'White', 'Cyan', 'Cyan', 'Cyan', 'DarkCyan')
$script:glitch = '#@%&*+=<>/\|0123456789ABCDEF'.ToCharArray()
$script:maskFrom = -1
$script:maskColor = 'DarkGray'
$script:maskGlitch = $false
$script:maskLine = ''
$script:maskLines = @()
$script:skipped = $false
$script:phase = ''
$script:logoTop = 0

function Row-Color([int]$y) {
    if ($logoH -le 1) { return 'Cyan' }
    $i = [int]($y * $palette.Count / $logoH)
    if ($i -ge $palette.Count) { $i = $palette.Count - 1 }
    if ($i -lt 0) { $i = 0 }
    return $palette[$i]
}

# ---------- 工具 ----------
function Wait-Ms([int]$ms) {
    if ($ms -le 0) { return }
    if ($Trace) { return }
    Start-Sleep -Milliseconds ([int]($ms * $factor))
}
function Set-Pos([int]$y) { try { if ($y -ge 0) { [Console]::SetCursorPosition(0, $y) } } catch { } }
function Get-Top { try { return [Console]::CursorTop } catch { return -1 } }
function Text-Width([string]$s) {
    $tw = 0
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if (($code -ge 0x1100 -and $code -le 0x115F) -or ($code -ge 0x2E80 -and $code -le 0xA4CF) -or ($code -ge 0xAC00 -and $code -le 0xD7A3) -or ($code -ge 0xF900 -and $code -le 0xFAFF) -or ($code -ge 0xFE30 -and $code -le 0xFE6F) -or ($code -ge 0xFF00 -and $code -le 0xFF60) -or ($code -ge 0xFFE0 -and $code -le 0xFFE6)) { $tw += 2 } else { $tw += 1 }
    }
    return $tw
}
function Center-Pad([string]$s) {
    $p = [int](($cw - (Text-Width $s)) / 2)
    if ($p -lt 0) { $p = 0 }
    return (' ' * $p)
}
function Center-PadW([int]$wd) {
    $p = [int](($cw - $wd) / 2)
    if ($p -lt 0) { $p = 0 }
    return (' ' * $p)
}
$interactive = $true
try { if ([Console]::IsOutputRedirected) { $interactive = $false } } catch { $interactive = $false }
$flushed = 0
try { while ([Console]::KeyAvailable -and $flushed -lt 20) { [void][Console]::ReadKey($true); $flushed++ } } catch { }
$ignoreSkipUntil = (Get-Date).AddMilliseconds(600)
function Test-Skip {
    if (-not $interactive) { return $false }
    if (-not $skipKey) { return $false }
    if ((Get-Date) -lt $ignoreSkipUntil) { return $false }
    try {
        if ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
            $script:skipReason = '按键跳过'
            return $true
        }
    } catch { }
    return $false
}

# ---------- 合成一行（主字形优先，未覆盖处显示阴影；支持遮罩）----------
function Write-ComposedRow([int]$i, [string]$pad, [string]$mainColor, [switch]$NoNL) {
    $parts = @()
    $curColor = $null
    $buf = ''
    for ($x = 0; $x -lt $totalW; $x++) {
        $ch = ' '
        $col = $mainColor
        $isGlyph = (($i -lt $logoH) -and ($x -lt $logo[$i].Length) -and ($logo[$i][$x] -ne ' '))
        if ($isGlyph) {
            if (($script:maskFrom -ge 0) -and ($x -ge $script:maskFrom)) {
                if ($script:maskGlitch) { $ch = $script:maskLine[$x] }
                else { $ch = $logo[$i][$x] }
                $col = $script:maskColor
            } else {
                $ch = $logo[$i][$x]; $col = $mainColor
            }
        } else {
            $si = $i - $dy
            $sx = $x - $dx
            if (($si -ge 0) -and ($si -lt $logoH) -and ($sx -ge 0) -and ($sx -lt $logo[$si].Length) -and ($logo[$si][$sx] -ne ' ')) {
                if (($script:maskFrom -ge 0) -and ($sx -ge $script:maskFrom)) {
                    # 阴影来源的字形还在解密中 -> 阴影也显示乱码，和字形同步解密
                    if ($script:maskGlitch) { $ch = $script:maskLine[$x] } else { $ch = $shadowChar }
                } else {
                    $ch = $shadowChar
                }
                $col = $shadowColor
            }
        }
        if ($col -eq $curColor) { $buf += $ch }
        else { if ($buf -ne '') { $parts += , @($curColor, $buf) }; $curColor = $col; $buf = [string]$ch }
    }
    if ($buf -ne '') { $parts += , @($curColor, $buf) }
    Write-Host $pad -NoNewline
    foreach ($p in $parts) { Write-Host $p[1] -NoNewline -ForegroundColor $p[0] }
    if (-not $NoNL) { Write-Host '' }
}

# ---------- 样式 1：打字机 ----------
function Reveal-Typewriter {
    $script:maskFrom = -1
    $script:logoTop = Get-Top
    for ($i = 0; $i -lt $totalH; $i++) {
        if (Test-Skip) { $script:skipped = $true; break }
        $col = 'Cyan'
        if ($i -lt $logoH) { $col = Row-Color $i } else { $col = 'DarkGray' }
        Write-ComposedRow $i $pad $col
        if ($i -lt $logoH) { Wait-Ms $revealMs } else { Wait-Ms ([Math]::Max(30, [int]($revealMs / 2))) }
    }
}

# ---------- 样式 2：乱码解密 ----------
function New-RandomLine {
    $line = New-Object 'char[]' $totalW
    for ($j = 0; $j -lt $totalW; $j++) { $line[$j] = $script:glitch[(Get-Random -Maximum $script:glitch.Length)] }
    return (-join $line)
}
function Reveal-Decrypt {
    $script:logoTop = Get-Top
    $script:maskFrom = 0
    $script:maskColor = 'DarkCyan'
    $script:maskGlitch = $true
    $script:maskLines = @()
    for ($k = 0; $k -lt 4; $k++) { $script:maskLines += (New-RandomLine) }
    $script:maskLine = $script:maskLines[0]
    for ($i = 0; $i -lt $totalH; $i++) { Write-ComposedRow $i $pad 'DarkGray' }
    Wait-Ms 140
    $steps = 18
    for ($s = 0; $s -le $steps; $s++) {
        if (Test-Skip) { $script:skipped = $true; break }
        $script:maskFrom = [int]($totalW * $s / $steps)
        $script:maskLine = $script:maskLines[$s % 4]
        for ($i = 0; $i -lt $totalH; $i++) {
            $col = 'Cyan'
            if ($i -lt $logoH) { $col = Row-Color $i } else { $col = 'DarkGray' }
            Set-Pos ($script:logoTop + $i)
            Write-ComposedRow $i $pad $col -NoNL
        }
        Wait-Ms 60
    }
    $script:maskFrom = -1
    Set-Pos ($script:logoTop + $totalH)
}

# ---------- 样式 3：数字雨 ----------
function Reveal-Rain {
    $script:logoTop = Get-Top
    $script:maskFrom = -1
    $rainChars = '01#@%&*+=<>|/\'.ToCharArray()
    $n = 10
    $rx = @(); $ry = @(); $rl = @()
    for ($k = 0; $k -lt $n; $k++) {
        $rx += (Get-Random -Minimum 0 -Maximum $totalW)
        $ry += (Get-Random -Minimum (-10) -Maximum 0)
        $rl += (Get-Random -Minimum 3 -Maximum 6)
    }
    for ($f = 0; $f -lt 10; $f++) {
        if (Test-Skip) { $script:skipped = $true; break }
        for ($i = 0; $i -lt $totalH; $i++) {
            $line = New-Object 'char[]' $totalW
            for ($j = 0; $j -lt $totalW; $j++) { $line[$j] = ' ' }
            for ($k = 0; $k -lt $n; $k++) {
                if (($rx[$k] -lt 0) -or ($rx[$k] -ge $totalW)) { continue }
                for ($t = 0; $t -lt $rl[$k]; $t++) {
                    if (($ry[$k] - $t) -eq $i) { $line[$rx[$k]] = $rainChars[(Get-Random -Maximum $rainChars.Length)] }
                }
            }
            Set-Pos ($script:logoTop + $i)
            Write-Host $pad -NoNewline
            Write-Host (-join $line) -NoNewline -ForegroundColor DarkGreen
            Write-Host ''
        }
        for ($k = 0; $k -lt $n; $k++) {
            $ry[$k] = $ry[$k] + 1
            if ($ry[$k] -gt ($totalH + 8)) { $ry[$k] = -6; $rx[$k] = (Get-Random -Minimum 0 -Maximum $totalW) }
        }
        Wait-Ms 70
    }
    for ($i = 0; $i -lt $totalH; $i++) {
        if (Test-Skip) { $script:skipped = $true; break }
        Set-Pos ($script:logoTop + $i)
        $col = 'Cyan'
        if ($i -lt $logoH) { $col = Row-Color $i } else { $col = 'DarkGray' }
        Write-ComposedRow $i $pad $col -NoNL
        Wait-Ms $revealMs
    }
    Set-Pos ($script:logoTop + $totalH)
    Write-Host ''
}

# ---------- 结尾：文案打字机 + 闪烁 + 徽章 ----------
function Finish-Block {
    if ($script:skipped) {
        Write-Host ''
        Write-Host ((Center-Pad '正在载入维修环境 ...') + '正在载入维修环境 ...') -ForegroundColor DarkGray
        Wait-Ms 500
        return
    }
    Set-Pos ($script:logoTop + $totalH)
    Write-Host ''
    if (-not $compact) {
        Write-Host $barPad -ForegroundColor DarkCyan
        Write-Host ''
    }
    $subTop = Get-Top
    for ($k = 1; $k -le $sub.Length; $k++) {
        if (Test-Skip) { $script:skipped = $true; break }
        Set-Pos $subTop
        Write-Host ((Center-Pad $sub) + $sub.Substring(0, $k)) -NoNewline -ForegroundColor White
        Wait-Ms 130
    }
    if ($script:skipped) { Write-Host ''; return }
    Write-Host ''
    Wait-Ms 150
    # —— 闪烁：白字 <-> 消失 交替，最后以白字落定 ——
    if ($blinkTimes -gt 0) {
        $blank = ' ' * (Text-Width $sub)
        for ($b = 0; $b -lt $blinkTimes; $b++) {
            if (Test-Skip) { $script:skipped = $true; break }
            Set-Pos $subTop
            Write-Host ((Center-Pad $sub) + $blank) -NoNewline
            Wait-Ms 140
            Set-Pos $subTop
            Write-Host ((Center-Pad $sub) + $sub) -NoNewline -ForegroundColor White
            Wait-Ms 300
        }
        Set-Pos $subTop
        Write-Host ((Center-Pad $sub) + $sub) -NoNewline -ForegroundColor White
        Write-Host ''
        Wait-Ms 120
    }
    # —— 徽章 ——
    Write-Host ''
    Write-Host ((' ' * [Math]::Max(0, [int](($cw - $badge.Length) / 2)))) -NoNewline
    Write-Host $badge -NoNewline -ForegroundColor Black -BackgroundColor White
    Wait-Ms 420
    Write-Host ''
    # —— 收尾 ——
    Write-Host ''
    if (-not $compact) { Write-Host $barPad -ForegroundColor DarkCyan }
    Write-Host ((Center-Pad '正在载入维修环境 ...') + '正在载入维修环境 ...') -ForegroundColor DarkGray
    Wait-Ms 1200
}

# ---------- 静态最终画面 ----------
function Show-Final {
    $bar = $L1 * [Math]::Min($totalW + 4, $cw)
    $padS = Center-PadW $totalW
    Write-Host ''
    Write-Host ((Center-Pad $bar) + $bar) -ForegroundColor DarkCyan
    $script:maskFrom = -1
    for ($i = 0; $i -lt $totalH; $i++) {
        $col = 'Cyan'
        if ($i -lt $logoH) { $col = Row-Color $i } else { $col = 'DarkGray' }
        Write-ComposedRow $i $padS $col
    }
    Write-Host ((Center-Pad $bar) + $bar) -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ((Center-Pad $sub) + $sub) -ForegroundColor White
    Write-Host ((' ' * [Math]::Max(0, [int](($cw - $badge.Length) / 2)))) -NoNewline
    Write-Host $badge -NoNewline -ForegroundColor Black -BackgroundColor White
    Write-Host ''
    Write-Host ''
}

# ---------- 时长预估 ----------
$revealMs = [Math]::Max(40, [int](1500 / $logoH))
if ($Trace) {
    $finish = ($sub.Length * 130 + 150) + ($blinkTimes * 440) + 120 + 420 + 1200
    if ($style -eq 'decrypt') { $plan = 300 + 180 + (42 * 42) + $finish }
    elseif ($style -eq 'rain') { $plan = 300 + (13 * 70) + ($totalH * $revealMs) + $finish }
    else { $plan = 300 + ($totalH * $revealMs) + $finish }
    Write-Host ('开场动画[' + $style + ']: ' + [int]($plan * $factor) + ' ms | 字母 ' + $LW + 'x' + $LH + ' | logo ' + $logoW + 'x' + $logoH + ' x' + $totalH + '(含阴影) | 闪烁 ' + $blinkTimes + ' 次 | 窗口 ' + $winW + 'x' + $winH + ' | ' + $speed)
    return
}
if ($NoAnim -or (-not $interactive)) { Show-Final; return }

trap {
    Write-IntroLog ('动画中断 | 样式=' + $style + ' | 阶段=' + $script:phase + ' | 错误=' + $_.Exception.Message + ' | 行号=' + $_.InvocationInfo.ScriptLineNumber)
    break
}

# ---------- 播放 ----------
try { Clear-Host } catch { }
$extraLines = 11
if ($winH -lt ($totalH + 11)) { $compact = $true; $extraLines = 3 } else { $compact = $false }
$topPad = [int](($winH - ($totalH + $extraLines)) / 2)
if ($topPad -lt 0) { $topPad = 0 }
Write-IntroLog ('动画开始 | 样式=' + $style + ' | 窗口 ' + $winW + 'x' + $winH + ' | 字母 ' + $LW + 'x' + $LH + ' | logo ' + $logoW + 'x' + $logoH + ' | 紧凑=' + $compact + ' | 清掉残留按键 ' + $flushed + ' | 跳过键=' + $skipKey)
$script:t0 = Get-Date
for ($i = 0; $i -lt $topPad; $i++) { Write-Host '' }

$barW = [Math]::Min($totalW + 4, $cw)
$barPad = Center-Pad ($L1 * $barW)
$pad = Center-PadW $totalW
$top = Get-Top

# 顶部边框展开
$script:phase = '阶段1-边框'
if (-not $compact) {
    for ($gw = 0; $gw -le $barW; $gw += [Math]::Max(2, [int]($barW / 6))) {
        if (Test-Skip) { $script:skipped = $true; break }
        Set-Pos $top
        Write-Host ((' ' * [Math]::Max(0, [int](($cw - $gw) / 2))) + ($L2 * $gw)) -ForegroundColor DarkCyan
        Wait-Ms 55
    }
    if (-not $script:skipped) { Set-Pos $top; Write-Host $barPad -ForegroundColor DarkCyan; Wait-Ms 120 }
    else { Set-Pos $top; Write-Host $barPad -ForegroundColor DarkCyan }
}

# 内容
$script:phase = '阶段2-' + $style
Write-IntroLog $script:phase
switch ($style) {
    'decrypt' { Reveal-Decrypt }
    'rain' { Reveal-Rain }
    default { Reveal-Typewriter }
}

# 结尾
$script:phase = '阶段3-结尾'
Write-IntroLog $script:phase
Finish-Block

Write-IntroLog ('动画完成 | 样式=' + $style + ' | 用时 ' + [int]((Get-Date) - $script:t0).TotalMilliseconds + ' ms')
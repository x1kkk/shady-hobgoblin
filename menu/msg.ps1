# ============================================================
# Pi Agent - 中文提示助手（msg.ps1）
# 供 start.bat 在异常分支调用；中文放在 .ps1 里可避免控制台
# 代码页差异导致的批处理解析问题。
# 用法：powershell -File msg.ps1 menufail | tooold
# ============================================================
param([string]$Case = 'menufail')

switch ($Case) {
    'menufail' {
        Write-Host ''
        Write-Host 'Pi Agent 菜单启动失败。' -ForegroundColor Yellow
        Write-Host '请手动运行下面这条命令（把 <U盘> 换成你的 U 盘盘符）：' -ForegroundColor Yellow
        Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File <U盘>:\menu\pi_menu.ps1'
        Write-Host '  （若没有便携 Pi，请改用 menu\main_menu.ps1）'
    }
    'tooold' {
        Write-Host ''
        Write-Host '这台电脑的系统太旧（Windows 9x），本工具支持 Windows XP/2003 及以上版本。' -ForegroundColor Yellow
    }
    default {
        Write-Host ('Pi Agent：' + $Case) -ForegroundColor Yellow
    }
}
Write-Host ''
Read-Host '按回车键退出' | Out-Null

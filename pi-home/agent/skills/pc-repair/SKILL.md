---
name: pc-repair
description: Windows 电脑通用体检、诊断与维修。当用户要求检查、诊断或修复系统/软件问题时使用（蓝屏、卡顿、磁盘空间、启动项、更新失败、服务异常等）。也负责把任务路由到 printer-share（打印问题）与 campus-network（校园网上网问题）两个专用技能。
---

# PC Repair 技能（Windows 体检与维修 · 总入口）

## 工具位置
以下路径均相对于 U 盘根目录（当前工作目录）：
- `core\ps\collect.ps1` 体检采集（v0.2；`-Fast` 快速，去掉为完整体检含 SFC/DISM）
- `core\ps\fix.ps1` 修复执行（F01~F21，自带备份与日志）
- `core\ps\ticket.ps1` 生成维修工单
- `ai\analyze.bat` DeepSeek 离线批量分析（老系统报告用）
- `reports\` 报告与工单输出目录

## 标准流程
### 第一步：体检
```
powershell -NoProfile -ExecutionPolicy Bypass -File core\ps\collect.ps1 -Fast
```
之后阅读**最新**一份 `reports\<时间戳>_<计算机名>\diagnosis.txt` 与 `findings.ini`。
报告分区：1 系统信息 / 2 内存与进程 / 3 磁盘 / 4 事件日志 / 5 蓝屏 / 6 驱动 / 7 网络 / 8 启动项 / 9 更新 / 10 安全 / 11 系统文件完整性（完整模式）/ **12 打印与打印服务** / **13 校园网接入** / 14 规则诊断结果。

### 第二步：分析
`findings.ini` 每行格式：`规则ID|严重度|修复ID|标题|详情`（修复ID 为空 = 需人工/AI 判断）。

规则速查：
- 系统类：R01 hosts 劫持、R02 DNS 失败、R03 网络栈异常、R04 代理、R05 SFC 损坏、R06 DISM 损坏、R07 可疑启动项、R08 磁盘空间、R09 服务异常、R10 蓝屏转储、R12 更新失败、R13 内存不足、R15 磁盘 SMART。
- 安全类：R11 未检测到杀毒、R14 防火墙关闭、R16 Defender 实时保护关闭。
- **打印类（12 区）**：R20 Spooler 未运行、R21 无默认打印机、R22 同端口多台打印机、R23 存在 WSD 端口、R24 队列卡死、R25 打印机 9100 不通、R26 共享主机 445 不通、R27 本机共享打印机（0x0000011b 相关）。
- **校园网类（13 区）**：R28 网卡被禁用、R29 169.254 地址（DHCP/认证失败）、R30 无默认网关（已排除虚拟网卡）、R31 DNS 无效、R32 存在代理设置、R33 生效默认路由指向虚拟网卡、R34 认证客户端未运行、R35 IP 冲突事件。

### 第三步：修复（必须经用户确认）
```
powershell -NoProfile -ExecutionPolicy Bypass -File core\ps\fix.ps1 -Ids F14,F20
```
（F07 清除可疑启动项需同时传 `-FindingIds R07`；F19 会询问打印机 IP。）
修复脚本自动备份到 `backups\<时间戳>\`、日志写入 `logs\actions.log`。

### 第四步：结论与工单
1. 把「问题定位 + 严重度 + 修复建议 + 已执行/待执行动作」写入本次报告目录的 `ai_analysis.txt`（UTF-8）；
2. 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File core\ps\ticket.ps1` 生成 `工单.txt`。

## 修复ID 速查（完整清单见 `fix.ps1 -List`）
| ID | 动作 | 风险 | 重启 |
|----|------|------|------|
| F01 | 刷新 DNS | 低 | 否 |
| F02 | 重置 Winsock/TCP-IP | 中 | 需要 |
| F03 | 重置 WinHTTP 代理 | 低 | 否 |
| F04 | 重置 hosts | 低 | 否 |
| F05 | sfc /scannow | 中 | 可能 |
| F06 | DISM RestoreHealth | 中 | 可能 |
| F07 | 清除可疑启动项 | 中 | 否 |
| F08 | 重置更新缓存 | 中 | 需要 |
| F09 | 清理临时文件 | 低 | 否 |
| F10 | chkdsk /f | 中 | 需要 |
| F11 | 重建 BCD | 高 | 需要 |
| F12 | 启用 Defender | 低 | 否 |
| F13 | 重置并开启防火墙 | 中 | 否 |
| F14 | 重启打印服务并清空队列 | 中 | 否 |
| F15 | 恢复自动获取 IP/DNS 并续租 | 中 | 否 |
| F16 | 清理系统/IE/环境变量代理 | 中 | 否 |
| F17 | 重新启用被禁用的网卡 | 中 | 否 |
| F18 | 共享打印兼容修复（0x0000011b） | 中 | 否 |
| F19 | 创建标准 RAW 9100 打印端口 | 低 | 否 |
| F20 | 上网故障急救（组合动作） | 中 | 否 |
| F21 | 重启校园网认证客户端服务 | 中 | 否 |

## 场景技能
- 打印问题 → 加载 `printer-share`（含 0x0000011b / 0x00000709 错误码对照与处置顺序）
- 校园网上网 → 加载 `campus-network`（含 802.1X 客户端检测、DHCP/DNS/代理/虚拟网卡判定树）

## 安全红线
- 禁止格式化/分区；禁止删除用户数据；禁止关闭杀软/防火墙。
- 修改注册表、系统文件、网络配置前必须先备份并说明风险。
- 结论必须基于报告证据，不得臆造故障。

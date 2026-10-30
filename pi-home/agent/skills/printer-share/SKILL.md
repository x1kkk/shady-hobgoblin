---
name: printer-share
description: 诊断与修复 Windows 打印机问题：SMB 共享打印机连不上、报 0x0000011b/0x00000709/0x0000007e、打印队列卡死、后台处理程序(Spooler)停止、网络打印机(IP 直连)端口错误或使用 WSD、驱动缺失或打印乱码。适用于校园办公电脑与学生笔记本。当用户提到"打印机/打印不了/共享打印/添加打印机/打印队列/默认打印机"时使用。
---

# 打印机故障处理流程（校园办公 / 学生机）

## 0. 铁律
1. **先只读诊断，再动手修复**；未经确认不要删除任何已安装的打印机。
2. 清空打印队列 = 任务会丢失，**必须先问用户"有没有正在打印的重要文件"**。
3. 不要改动他人电脑/打印服务器上的设置（`0x0000011b` 的服务端修复需要校方 IT 同意）。
4. 每步修复后要复验：`Get-Service Spooler`、`Get-PrintJob`、必要时打印测试页。
5. 在还原卡/云桌面环境里做修改 = 白做，先人工确认环境（本候选版没有附带 exam-room 技能）。

## 1. 快速定位（按顺序，全部只读）

### 1.1 后台处理程序与队列
```powershell
Get-Service Spooler | Select-Object Name,Status,StartType
Get-Printer | Select-Object Name,DriverName,PortName,Shared,Published
Get-PrintJob -PrinterName * | Select-Object PrinterName,Id,DocumentName,JobStatus,SubmittedTime
```
判读：
- Spooler 不是 Running → 队列完全不动 → **F14**
- 有任务长时间 `Printing/Spooling` 而打印机无动作 → 卡死任务阻塞队列 → **F14**
- 队列为空却毫无反应 → 端口/驱动问题（见 1.3/1.4）

### 1.2 默认打印机与重复安装
```powershell
Get-CimInstance Win32_Printer | Select-Object Name,Default,PortName,DriverName,Network
```
判读：
- 同一 IP/共享路径装了多台（出现 "(副本 1)" 之类）→ 默认打印机可能指向已失效的那台
- 全部 `Default=False` → 没有默认打印机（Office 会报"未安装打印机"）

### 1.3 端口
```powershell
Get-PrinterPort | Select-Object Name,PrinterHostAddress,PortNumber,Protocol
Test-NetConnection <打印机IP> -Port 9100
```
判读：
- **WSD 端口**（名字含 WSD / `Protocol=WSD`）→ 校园跨网段环境下经常时好时坏 → 建议改标准 **RAW 9100**（**F19**）
- `PrinterHostAddress` 为空或 IP 已变更 → 重建端口（**F19**）
- 端口 IP 不通 → 先解决网络，再谈打印

### 1.4 驱动
```powershell
Get-PrinterDriver | Select-Object Name,PrinterEnvironment,Manufacturer
Get-PnpDevice -Class Printer | Where-Object { $_.Status -ne 'OK' }
```
- 有异常状态设备 / 提示"找不到驱动" → 驱动缺失（x86/x64 不匹配是共享打印的经典坑）
- 打印乱码（中文变方块）→ 驱动型号/版本不匹配，重装官方驱动

### 1.5 共享可达性（SMB，最关键）
```powershell
Test-NetConnection <打印机主机名或IP> -Port 445
Test-Path '\\主机名\共享名'
Get-SmbClientConfiguration | Select-Object RequireSecuritySignature,EnableInsecureGuestLogons
```
判读：
- 445 不通 → 网络/防火墙/对方未开机或共享服务停止
- 提示"找不到网络路径" → 共享权限或凭据问题
- 提示"组织安全策略阻止未经身份验证的来宾访问" → 客户端禁止来宾登录，应改用**账号连接**
- 报 **0x0000011b** → 服务端打了 PrintNightmare 补丁后的 RPC 打印限制（服务端修复 **F18**；客户端应急方案：**改用 IP 直连**）
- 报 **0x00000709** → 先设默认打印机，再按 **F18** 方向排查

### 1.6 凭据
```powershell
cmdkey /list
net use \\主机名\IPC$ /user:账号 *
```
- 校园办公机多为域账号共享；学生机通常没有凭据 → 引导向共享者索取账号，或让共享方开启"允许 Guest"（安全上有取舍）

## 2. 症状 → 根因 → 动作 对照表

| 症状 / 错误码 | 常见根因 | 动作 |
|---|---|---|
| 点打印毫无反应、队列不动 | Spooler 停止或卡死 | **F14** |
| 长期停在"正在打印" | 卡死任务阻塞队列 | **F14**（需先确认无重要任务） |
| **0x0000011b** | 服务端 RPC 打印限制（KB50055xx 之后） | 服务端 **F18**（需校方同意）；客户端改 **IP 直连** |
| **0x00000709** | 默认打印机键异常 / RPC 限制 | 先设默认打印机，再走 **F18** 方向 |
| 找不到网络路径 | SMB 445 不通 / 共享权限 | 查 445 + 共享权限；用账号连接 |
| 阻止未经身份验证的来宾访问 | Win10/11 客户端默认策略 | 改用账号连接（推荐） |
| WSD 打印机时好时坏 | WSD 依赖多播发现，跨段不稳 | **F19** 改 RAW 9100 |
| 打印乱码 / 中文方块 | 驱动不匹配 | 重装官方驱动（给出厂商驱动页） |
| 提示找不到驱动 | 共享端驱动与客户端架构不符 | 客户端"使用本地驱动"方式添加 |
| 任务删不掉 | Spooler 占用队列文件 | **F14** |

## 3. 修复动作（统一走 fix.ps1，需用户确认）
- **F14** 重启打印后台处理程序并清空队列（先备份 `spool\PRINTERS` 里的队列文件）
- **F18** 共享打印兼容修复（设置 `RpcAuthnLevelPrivacyEnabled=0`，属安全权衡，需明确同意）
- **F19** 为指定 IP 重建标准 RAW 9100 打印端口（可绑定到现有打印机）
- 人工步骤（脚本不自动做）：重装驱动、重新添加打印机、调整共享凭据

## 4. 禁止事项
- 不自动删除用户的打印机（除用户明确指定）
- 不擅自改动打印服务器/共享方电脑
- 不在打印进行中清空队列（先告知会丢任务）
- 不在还原卡/云桌面环境做修改
- 不改动校方统一部署的打印策略（如组策略下发的端口/驱动）

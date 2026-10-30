---
name: campus-network
description: 诊断与修复校园网无法上网问题：DHCP 获取失败(169.254.x.x 地址)、802.1X 认证客户端异常(锐捷/深澜 Srun/H3C iNode/Dr.COM)、IP 冲突、网关与 DNS 被改、代理残留(WinHTTP/IE/环境变量)、网卡被禁用、虚拟网卡与加速器抢占默认路由、DNS 解析失败。适用于校园办公电脑与学生笔记本。当用户说"上不了网/连不上校园网/认证失败/网速异常/网页打不开/网络诊断"时使用。
---

# 校园网上网故障处理流程（802.1X 认证环境）

## 0. 铁律
1. **先只读、后修改**；任何网络配置改动前，脚本都会先把当前配置写进报告（`ipconfig /all`）。
2. **不能想当然改 IP**：实验室/办公区可能是固定 IP。先问用户"这台机器原本是自动获取还是固定 IP？"，得到确认再动。
3. 校园网认证客户端（锐捷/深澜/iNode/Dr.COM）是第三方安全组件：**只检查、只重启服务，不擅自卸载或重装**。
4. **绝不尝试绕过 802.1X 认证**（不装虚拟网卡共享、不改 MAC 欺骗）。
5. 若是"多台同时上不了网" → 属于网络侧故障（上联/认证服务器/VLAN），直接建议报修网管，不要在单机上折腾。

## 1. 快速定位（按顺序，全部只读）

### 1.1 链路与地址
```powershell
Get-NetAdapter | Select-Object Name,Status,LinkSpeed,MacAddress
Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer
```
判读：
- `Status` 不是 `Up`（网线已插）→ 网卡被禁用或驱动异常 → **F17**
- IP 是 **169.254.x.x** → DHCP 没拿到地址（认证未通过最常见，其次 DHCP/端口故障）→ 先看 1.2，再 **F15**
- IP 正常但网关为空 → DHCP 半失败或静态误配

### 1.2 认证客户端（802.1X 关键环节）
```powershell
Get-Process | Where-Object { $_.ProcessName -match '(?i)ruijie|supplicant|srun|inode|drcom|8021|h3c|njstar' }
Get-Service | Where-Object { $_.DisplayName -match '锐捷|深澜|认证|802\.1|iNode|Srun|Supplicant|Dr' }
```
判读：
- **客户端没装** → 校园网接入前提不满足（引导用户到学校网络自助页面下载对应客户端）
- 客户端已装但进程/服务未运行 → **F21** 重启认证相关服务
- 认证报错 → 引导核对：账号密码、是否欠费、是否 MAC 绑定到期、是否需要先在自助系统登记设备
- 认证成功但仍无网 → 继续 1.3 / 1.4

### 1.3 连通性三段定位（网关 / 外网 IP / 域名）
```powershell
Test-NetConnection <默认网关> -InformationLevel Quiet
Test-NetConnection 223.5.5.5 -InformationLevel Quiet
Resolve-DnsName www.baidu.com -ErrorAction SilentlyContinue
```
组合判读：

| 网关 | 外网IP | 域名 | 结论 | 动作 |
|:--:|:--:|:--:|---|---|
| ✅ | ✅ | ❌ | DNS 问题 | **F01** + 把 DNS 改回自动获取或校方指定 |
| ✅ | ❌ | ❌ | 出口/认证后未放行 | 认证问题或网管侧，转 1.2 / 报修 |
| ❌ | ❌ | ❌ | 本地链路或认证未通过 | 1.1/1.2；也可能是端口被封（换墙插口测试） |

### 1.4 代理残留（校园/学生机高频）
```powershell
netsh winhttp show proxy
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer
Get-ChildItem env: | Where-Object { $_.Name -match '(?i)proxy' }
```
判读：存在加速器遗留 / 旧代理 → **F16** 清理（先备份原值）
⚠️ 若学校**要求**使用明文代理上网，则不要清，先与用户确认。

### 1.5 虚拟网卡与加速器抢占路由（学生机高频）
```powershell
Get-NetAdapter | Where-Object { $_.InterfaceDescription -match '(?i)VMware|VirtualBox|Radmin|TAP|TUN|WireGuard|OpenVPN|ZeroTier|Clash|加速' }
Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias,NextHop,RouteMetric
```
判读：**默认路由指向了虚拟网卡** = "连着网但打不开网页"的经典原因 → 临时禁用该虚拟网卡（只建议，不自动删）。

### 1.6 IP 冲突与 ARP
```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Tcpip'} -MaxEvents 50 |
  Where-Object { $_.Id -in 4198,4199 } | Select-Object TimeCreated,Id,Message
arp -a | Select-String <网关IP>
```
- 出现 4198/4199 → IP 冲突：静态 IP 的机器改自动获取，或找网管重新分配
- 网关 MAC 频繁变化 → 网络侧问题，报修

## 2. 症状 → 根因 → 动作 对照表

| 症状 | 常见根因 | 动作 |
|---|---|---|
| 169.254 地址 / 无 IP | 认证未通过、DHCP 未放行、网口故障 | 先认证（1.2），再 **F15** |
| 认证客户端服务停止 | 客户端服务异常 | **F21**（只重启，不重装） |
| 网关通、域名不通 | DNS 被改/被劫持 | **F01** + 恢复自动 DNS |
| 网页打不开但 QQ 能上 | DNS 或代理问题 | **F01** / **F16** |
| 连着网但完全无流量 | 默认路由被虚拟网卡抢走 | 禁用虚拟网卡（1.5） |
| 网卡 Down | 网卡被禁用 | **F17** |
| 反复断线/改过 IP 后异常 | 网络协议栈损坏 | **F02**（需重启） |
| 多台同时故障 | 网络侧 | 报修网管，不在单机折腾 |

## 3. 修复动作（统一走 fix.ps1，需用户确认）
- **F01** 刷新 DNS 缓存
- **F02** 重置 Winsock/TCP-IP（需重启）
- **F15** 恢复"自动获取 IP/DNS"并释放续租（**必须先确认原本就是自动获取**）
- **F16** 清理系统/IE/环境变量代理（先备份原值）
- **F17** 重新启用被禁用的网卡
- **F21** 重启校园网认证客户端相关服务（只重启）
- **F20** 上网故障急救：按固定顺序跑完并输出每步结果（启用网卡 → flushdns → 重置代理 → 仅对现有 DHCP 接口续租 → 验证三段连通性）

## 4. 禁止事项
- 不绕过 802.1X 认证，不做 MAC 欺骗
- 不擅自卸载/重装认证客户端
- 不改实验室机器的静态 IP（未确认前）
- 不清除校方要求的代理配置
- 不删除虚拟网卡（最多建议临时禁用）

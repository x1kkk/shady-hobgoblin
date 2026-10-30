# 使用、权限和数据

本地诊断与 AI 分开：`start.bat` 根据运行时是否存在选择 Pi 或传统菜单；无需 API Key 即可使用传统菜单体检/诊断规则、查看报告、维修及工单。可直接用 `powershell -NoProfile -File menu\main_menu.ps1 -NoElevate`。普通入口不自动提权；管理员运行 `tools/menu-elevate.vbs` 是使用者显式选择，UAC 可以拒绝。修复及部分完整扫描需要管理员；非管理员快速体检可能缺少部分数据。

诊断会在本工具目录写入 reports；联网连通性测试会发送 ICMP/DNS 请求并探测已配置的打印机端口。这里的“只读体检”指不执行维修，不等于零写文件、零网络或 Windows 自身零日志。完整扫描会调用 SFC verifyonly/DISM scanhealth。此次整理没有运行任何体检或维修。

`reports`、`logs`、`backups`、`downloads`、Pi sessions 在运行时按需创建，公开包可为空/不存在。真实报告含机器名、账户名、IP/MAC、事件内容、启动命令及代理配置；代理信息可能包含登录凭据。不得提交至公开源码仓库。备份、注册表导出和日志同样属于私人数据。运行代码当前尚不能保证每个修复的备份成功即停止条件，见 SECURITY-REVIEW.md；执行高风险动作前须另行完整备份。

AI 有两条入口：

- 传统菜单 [7] 在当前 `config.ini` 保存本人 Key（明文），`base_url` 默认 DeepSeek 官方地址，`model` 默认 deepseek-chat。AI 分析和批量分析仍调用原 VBS HTTP 代码；每份报告上传前要求输入 `UPLOAD`。批量“离线分析”指将旧电脑报告带回联网现代电脑分析，并非本地离线模型推理。
- 便携 Pi 从 `pi-home/agent` 加载准则、技能、提示词与权限扩展。通过 `/login` 填写自己的凭据，或由当前进程传入 `DEEPSEEK_API_KEY`；默认空 auth 不阻止传统诊断。要用自定义服务，将 `models.example.json` 复制成 `models.json` 并自行检查地址/参数，不在模板中写入真实 Key。没有私有 shellPath，Pi PowerShell 工具通过系统发现；`!`/`!!` 的 Bash 入口及 Git 归档可能需要 Git for Windows。

Pi 会将你输入的内容、选取的报告与工具结果发送给选定模型服务。进入专项维修 AI 会话即需要你先审阅数据边界，不要假定权限门禁也是上传过滤器。禁止将 API Key、客户密码或敏感原始日志输入到聊天中。自动替换机器名/用户名不是完整匿名化；必要时先在私人工作副本手动删去敏感内容。AI 输出需人工复核，不等于修复已验证。

私人归档独立于开源源码仓库。首次本地归档可自行运行：

```powershell
powershell -NoProfile -File tools\setup_archive.ps1 -RepoDir "$env:USERPROFILE\repair-records"
```

该操作会创建本地独立 Git 仓库并写入被忽略的 `archive.local.json`，默认 `allowRemote=false`、`autoArchive=false`。Git 提交身份由使用者自己配置，不自动修改全局 Git。归档仓库必须位于源码树之外，禁止使用源码仓库或其它 Git 仓库的子目录。

远程归档：先在自己的平台手动准备**私有**仓库，通过 Git Credential Manager 或 SSH 配置本人认证；再运行带无秘密 `-RemoteUrl` 的 setup 并显式传入 `-AllowRemote`，输入 `UPLOAD`。工具无法自动证明远端是私有仓库，使用者必须确认仓库可见性、授权与报告所有者同意。Token 参数已禁用，不将令牌置入命令行、Git URL 或日志。配置成功后手动菜单 [12] / archive_records.ps1 可提交、pull、push；若希望会话结束自动归档，再手动将 `archive.local.json` 的 `autoArchive` 设为 true。出工单自动归档亦受此开关控制。

归档内容含工单、AI 结论、处理办法、机器名、报修人和处理人，可能需要组织许可。归档不是公开发布流程，绝不能把记录仓库合并进源码。每周清理仍保留 DELETE/-Yes 授权方式，但其完整性条件存在已知问题，正式修复之前建议不启用定时清理。

U 盘遗失意味着明文 Key、记录和备份可能暴露：由用户自行停用/轮换对应凭据。公开构建会恢复空配置；不会擦除原工作副本的凭据、数据或 Git 历史。

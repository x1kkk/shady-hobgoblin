# Pi Agent Windows 维修 U 盘工具 · 0.1.0-rc1

首个开源候选源码包，供审查与后续发布准备。包含本地体检与诊断规则、F01–F21 维修动作、AI 分析、Pi 技能/提示词/权限扩展、工单、U 盘构建、同步与私人归档。API 调用代码完整保留，使用者需要自己的账户。

**这是候选源码版，存在已知维修安全问题；尚不能称为安全正式发布版。** 本次只做静态及离线发布隔离验证，没有执行维修、真实 AI 请求或归档上传。详见 [安全问题](docs/SECURITY-REVIEW.md) 与 [验证记录](docs/VALIDATION.md)。

本目录不含 Node/Pi/rg/fd 大型二进制，也不含真实凭据、会话、工单、报告和备份。没有运行时也能从 `start.bat` 进入传统菜单进行本地诊断；缺少 API 配置只影响 AI 功能。现代 Pi AI 模式须先按 [依赖组装说明](docs/DEPENDENCIES.md) 组装便携运行时。

使用：双击 `start.bat`，或普通权限打开 `powershell -NoProfile -File menu\main_menu.ps1 -NoElevate`。普通入口现在默认普通权限；选择维修需要使用者另行打开管理员入口。`start_pi.bat` 直接启动已组装的 Pi；`tools/menu-launch.cmd` 是随位置变化的入口，不分发绑定原机器的 `.lnk`。Win7/XP 路径仍保留，但旧平台兼容性与现代 TLS 未重新实测，Pi/Node 部分面向 Windows 10/11 x64。

AI 配置：传统脚本菜单 [7] 写入当前副本 `config.ini` 的 `api_key`；Pi 使用 `/login` 或进程环境变量 `DEEPSEEK_API_KEY`，其独立凭据保存在 `pi-home/agent/auth.json`。`config.example.ini`、`auth.example.json`、`models.example.json` 是无秘密示例。两条 AI 路径的凭据不会自动互相复制。自定义模型、代理、服务地址由使用者配置，避免将含秘密 URL 写入可发布文件。

公开构建（无网络、无自动执行运行时、无需管理员）：

```powershell
# 输出必须是不存在的新目录。代码包可以在干净环境直接组装。
powershell -NoProfile -File make_usb.ps1 -Target .\dist\public-source -SkipRuntime -NoKey -Quiet
# 完整便携组装需提供审查过的离线依赖清单
powershell -NoProfile -File make_usb.ps1 -Target .\dist\public-usb -RuntimeManifest <离线依赖目录>\runtime-manifest.json -NoKey -Quiet
```

默认 `-Mode Public`：仅复制 `release/files.json` 中经哈希固定的文件；配置永远来自 `release/defaults`。运行过的当前目录中的 `config.ini`、auth、settings、历史会话与任何额外嵌套文件均不会进入发布物。清单不替代秘密扫描：源码修改后须重新人工审查与更新哈希。不要从整个工作目录直接压缩或 `git add -f`。Git 忽略规则、`.gitattributes export-ignore` 与构建清单分别生效。

私人现场部署（绝不可公开）：

```powershell
powershell -NoProfile -File make_usb.ps1 -Target .\dist\private-usb -Mode Private -RuntimeManifest <离线依赖清单> -IncludeCredentials -CredentialRoot <本人配置所在目录>
```

只显式复制该目录的 `config.ini` 与 `pi-home/agent/auth.json`，需要输入 `PRIVATE`；不读取宿主用户配置、不复制会话和现场数据。`-NoKey` 和 `-IncludeCredentials` 互斥；`Private -NoKey` 与无凭据构建相同。私人部署带明显禁止公开标记。公开构建发现旧目标就失败，不以旧文件冒充复制成功。`-FullRuntime` 不再隐式采集本机环境；需提供完整离线依赖清单。`-NoSelfTest` 兼容接受，但所有构建都不自动运行依赖。

`tools/fix_usb.ps1 -UsbRoot <U盘目录> -SkipRuntime` 会在 U 盘下创建全新安装目录。原权限修复能力保留为显式 `-RepairPermissions`（需使用者自行打开管理员终端并输入 `ACL`），不会自动提权。同步默认只处理双方审核清单内源码；`-DryRun` 不创建目录、不写文件，配置与数据默认不参与，私人凭据同步需 `-Mode Private -IncludeCredentials`。

归档默认关闭。按 [使用与数据说明](docs/USAGE.md) 配置独立私人仓库及 `archive.local.json`；远程上传必须显式启用，认证使用 Git Credential Manager 或 SSH，禁止 Token 命令参数或含令牌的 URL。自动归档默认关闭。

自有代码按 [MIT License](LICENSE) 准备公开，版权署名和来源待维护者最终确认，见 [许可范围](docs/LICENSING.md)；第三方仍遵循 [原有声明与许可](THIRD_PARTY_NOTICES.md)。简明操作见下方，详细配置见 [使用说明](docs/USAGE.md)，数据去向见 [隐私说明](PRIVACY.md)。

首次使用：运行 `start.bat` → 传统菜单选快速体检并查看报告 → 如需 AI，配置本人账户后选择分析 → 如需维修，先备份并使用管理员入口逐项确认 → 按需生成工单、配置私人归档。Pi AI 模式先组装运行时，再用 `/login` 配置自己的账户。公开源码不携带使用者账户或现场数据。

公开步骤见 [发布准备](docs/RELEASE.md)。已备好 [签名政策草稿](SIGNING_POLICY.md) 与 [SignPath Foundation 申请材料](docs/SIGNPATH-APPLICATION.md)，尚未申请、获批或提供签名；签名不能保证安全软件一定放行。

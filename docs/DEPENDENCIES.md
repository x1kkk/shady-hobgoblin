# 干净环境依赖获取与组装

本候选目录仅含项目源码与已有的第三方许可证文本/元数据，未重复复制约 165 MiB 的运行时、8 MiB 的 rg/fd，也未联网下载。传统菜单使用 Windows 内置 cmd/Windows PowerShell/WSH；AI Pi 模式需要便携 Node 和 Pi 包。获取依赖是使用者后续单独授权的步骤，当前构建器本身不下载、不扫描已安装软件、不执行依赖自检。

本地观察值（不等于上游验证）：Node PE 产品版本 24.15.0，签名状态 Valid；Pi package.json 为 @earendil-works/pi-coding-agent 0.85.1、MIT，仓库字段指向 https://github.com/earendil-works/pi；rg.exe/fd.exe 未签名、无 PE 版本，当前无法可信确认版本。具体本地 SHA256 与来源状态在 third-party/observed-tools.json。137 条 package 元数据在 observed-packages.json；6 条缺 license 声明、23 条缺邻接许可证文件。这些均是正式二进制发布前待核对项，不把本地文件命名视作来源证明。

从零准备建议（在单独依赖目录中进行）：

1. 从 https://nodejs.org/dist/ 获取与维护者最终确认的锁定版本一致的 Windows x64 ZIP；使用官方 SHASUMS256.txt 与其签名验证压缩包，解压保留 LICENSE 与所有必要 NOTICE。不在项目内执行安装器，不从维护者 PATH 抽取 node.exe。现观察到的 24.15.0 必须先确认上游存在及支持情况；未经联网核实，不预填虚构下载证明。
2. 从 https://www.npmjs.com/package/@earendil-works/pi-coding-agent 获取明确版本 0.85.1，并核对官方源包、仓库标签/提交、npm integrity、依赖锁。可在独立目录建立 package.json 固定精确版本，再由用户执行 `npm install --ignore-scripts --save-exact @earendil-works/pi-coding-agent@0.85.1`，审查并保存 package-lock.json；之后 CI 用 `npm ci --ignore-scripts`。这条命令需要联网，**本次未执行**。npm 包精确版本不自动锁定首次解析的全部传递依赖，正式发布必须审核并保留锁文件。
3. 将完整 Pi 包与其必需依赖放在离线目录 `runtime/pi/node_modules/...`，将官方 Node ZIP 的 node.exe 放入 `runtime/pi/`。保留上游包原文件、版权、许可证与数字签名；不要以本地剪枝副本补缺或直接复用来源不明二进制。候选包提供 runtime/pi/pi.cmd 的相对路径启动包装器，不属于上游文件。
4. rg 来源 https://github.com/BurntSushi/ripgrep （MIT OR Unlicense）；fd 来源 https://github.com/sharkdp/fd （MIT OR Apache-2.0）。选择明确发行版本的 Windows x64 ZIP，核对发布校验/签名和完整许可证；放入 `pi-home/agent/bin/rg.exe`、`fd.exe`，必要声明放到 `third-party/runtime-notices/`。当前原 exe 版本未知，正式组装时须记录版本、下载 URL、压缩包哈希、提取文件哈希和验证依据。不得替第三方代码改许可证或自行重签其文件。
5. Git for Windows 仅用于 Git 归档及 Pi 的可选 Bash 入口，来源 https://gitforwindows.org/ ，项目主体 GPL-2.0、套件另有第三方许可。建议由用户另行安装官方签名版本，不将宿主安装目录打包。本工具默认 PowerShell 工具集可用于维修；WSH 在部分 Windows 版本为可选/已禁用功能，VBS AI 路径需用户系统支持。

离线依赖目录根部放 `runtime-manifest.json`（人工审核后生成，不从当前工作目录自动收集）：

```json
{
  "reviewed": true,
  "noticesReviewed": true,
  "files": [
    {"source": "runtime/pi/node.exe", "destination": "runtime/pi/node.exe", "sha256": "替换为审核文件的64位SHA256"}
  ]
}
```

示例中的占位不是有效清单；构建会拒绝。清单必须逐个列出全部运行时文件、所需包装器及许可证，不能只列 node.exe。依赖目标仅允许 runtime/pi、rg/fd 两个 bin 文件及 third-party；不允许 auth/settings/config、运行数据、链接或目录跳转。源码包的 `runtime/pi/pi.cmd` 已包含，依赖清单勿重复覆盖。构建会要求 node.exe、pi.cmd、Pi CLI、rg.exe 和 fd.exe，逐文件验证源和复制后哈希；它不证明你的清单已包含每个运行依赖，需后续隔离环境验证。未给清单时必须显式 `-SkipRuntime`。

候选 runtime/pi/pi.cmd 从 `%~dp0` 使用同目录 node.exe 与相对 Pi CLI，避免依赖已安装环境。完整二进制发布前还需在没有全局 Node/Pi 的干净 Windows VM 验证版本、模块加载与权限扩展（禁网、虚构输入），再另行授权做 AI 与真实维修验证。此次没有生成可复现二进制构建证明，也没有完成第三方来源和许可证缺口调查。

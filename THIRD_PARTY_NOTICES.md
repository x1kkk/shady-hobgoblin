# 第三方与许可状态

第三方代码不因本项目候选整理而变更权利归属。当前候选版未附原大型运行时和工具 exe，仅保存从原 runtime package.json 观察到的名称、版本、声明许可证、仓库字段及已有 LICENSE/COPYING/NOTICE 原文。元数据不是完整来源证明；LICENSE 文本目录中的 node_modules 字样只是原包路径分类，不含运行时模块。

| 组件 | 已观察版本/状态 | 来源与许可 |
|---|---|---|
| Node.js | PE 产品版本 24.15.0，本地 Authenticode Valid；未联网对照上游 | https://nodejs.org/ ，MIT 及捆绑第三方条款；未附二进制，正式组装须保留发行版完整 LICENSE |
| Pi coding agent | package.json 0.85.1 | https://github.com/earendil-works/pi ，包声明 MIT，原许可证文本保存在 third-party/licenses |
| Pi 及依赖元数据 | 137 条，可能包含非根包示例 package.json，非最终 SBOM | MIT/BSD-3-Clause/Apache-2.0/ISC/Unlicense/BlueOak-1.0.0/0BSD；6 条无 license 声明，23 条无邻接 LICENSE，待逐项查明 |
| ripgrep / rg.exe | 无 PE 版本、NotSigned，版本来源未证实 | https://github.com/BurntSushi/ripgrep ，上游 MIT OR Unlicense，当前原 exe 未分发 |
| fd / fd.exe | 无 PE 版本、NotSigned，版本来源未证实 | https://github.com/sharkdp/fd ，上游 MIT OR Apache-2.0，当前原 exe 未分发 |
| Git for Windows（可选宿主工具） | 未捆绑、未固定 | https://gitforwindows.org/ ，Git 主体 GPL-2.0 及其套件第三方条款；使用者另装 |
| Windows cmd / PowerShell / WSH | 宿主操作系统组件 | 微软相应系统条款；不作为本项目代码重新许可 |

`third-party/observed-packages.json` 与 `observed-tools.json` 只记录本地观察，不含私人地址、账号和凭据。未确认来源及缺许可证部分必须在二进制正式分发前解决；不能用 MIT 建议覆盖第三方许可或宣称未知来源代码属于本项目。

本项目自有代码按根目录 LICENSE 的 MIT 许可准备公开；适用范围及版权署名确认事项见 docs/LICENSING.md。上述第三方保持各自原许可与版权，根 MIT 不替代它们。对当前源码未发现明显的 MIT 冲突证据，但缺少逐文件来源记录，不能据此认定所有未知来源内容均已获得授权。

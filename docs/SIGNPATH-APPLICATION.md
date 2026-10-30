# SignPath Foundation 申请材料草稿

用途：供个人维护者准备免费签名申请；不是已经提交或获批的申请。已核对 https://signpath.org/terms.html 的公开要求；具体资格、脚本签名及构建平台接受情况仍需服务方确认。本文不编造身份、用户规模或审核结果；私人申请邮箱不写入公开源码。

申请信息：

| 字段 | 拟填写内容 |
|---|---|
| 项目 | Pi Agent Windows 维修 U 盘工具，0.1.0-rc1 源码候选版；仓库名 shady-hobgoblin |
| 维护者及联系 | GitHub 维护者 x1kkk：https://github.com/x1kkk ；申请邮箱由维护者在官方表单中填写，不在本文件公开 |
| 公开仓库 / 项目主页 | https://github.com/x1kkk/shady-hobgoblin |
| 许可证 | 自有代码 MIT，见 LICENSE；第三方独立许可见 THIRD_PARTY_NOTICES.md；权属确认见 docs/LICENSING.md |
| 用途 | 个人便携 Windows 诊断与维修工具，包含本地诊断、用户确认后的维修、可选 AI 分析、技能/提示词、工单和私人归档 |
| 签名对象 | 拟签本项目自有可签名产物；目前以脚本为主，需向基金会确认 PowerShell 等格式、构建平台和申请资格 |
| 构建证据 | make_usb.ps1 Public 模式；release/files.json 的固定文件/哈希；依赖组装说明 docs/DEPENDENCIES.md。当前没有远程 CI、已完成的签名集成或可复现二进制证明 |
| 审批角色 | 作者、审核与拟定签名批准者：x1kkk；个人维护，无独立多人审批制度。GitHub/SignPath 多因素认证状态待维护者确认，不宣称已启用 |
| 隐私 / 签名政策 | https://github.com/x1kkk/shady-hobgoblin/blob/main/PRIVACY.md 和 https://github.com/x1kkk/shady-hobgoblin/blob/main/SIGNING_POLICY.md |

可复制的项目介绍：

> 本项目是个人维护的便携 Windows 维修工具，拟以 MIT 发布自有源码。功能包括本地体检与规则诊断、经用户确认的管理员维修、可选的用户自备账户 AI 分析、维修技能与提示词、工单以及私人 Git 归档。公开源码及 Public 构建排除真实凭据和现场数据，第三方工具保持各自许可与上游签名。当前提交为候选版，已记录维修风险，尚未获得 SignPath Foundation 签名。希望确认项目是否符合免费签名资格、当前脚本形式可签的产物以及所需的受控构建集成。

后续顺序：维护者确认署名/权属 → 公开干净源码并补仓库链接 → 按基金会最新要求准备受支持的构建来源与审批账户 → 人工提交申请 → 审核通过后再配置签名并更新政策。若需要 CI，先根据服务方支持的平台补最小构建流程；不要为了申请额外包装 exe、混淆脚本或修改第三方签名。

无需先购买服务。本材料不承诺免费申请必然获批；不把申请流程尚未完成写成产品功能限制。

## 可复制到官方表单的英文介绍

Project: Pi Agent Windows Repair USB Toolkit (repository: shady-hobgoblin)

Repository: https://github.com/x1kkk/shady-hobgoblin

Maintainer: x1kkk (https://github.com/x1kkk)

This is a personally maintained, MIT-licensed Windows diagnostics and repair toolkit intended for small-scale use. It includes local diagnostics, administrator repair actions, optional AI analysis using the user's own account, repair prompts, ticket generation and optional private Git archiving. Public source packages exclude credentials, session history and repair records. Third-party components retain their own licenses and upstream signatures.

The current version is a source release candidate. It has no remote CI or signing integration yet. We would like to confirm eligibility for Foundation sponsorship and whether our own PowerShell scripts can be signed through a supported, verifiable build pipeline. We are not requesting re-signing of third-party runtimes or tools.

The toolkit can make significant system configuration changes. In particular, the optional F18 printer compatibility action can weaken an RPC security setting. Known authorization, backup and report-binding limitations are documented at https://github.com/x1kkk/shady-hobgoblin/blob/main/docs/SECURITY-REVIEW.md . We disclose these limitations for eligibility review and do not claim compliance or production safety has been established.

Code authorship, review and proposed signing approval are currently handled by the single maintainer, x1kkk. Multi-factor authentication status will be confirmed by the maintainer during onboarding. No Foundation sponsorship or signature has been granted.

## 提交前由维护者确认

- 在官方表单填写可收信的联系邮箱；不要使用 Git 提交用的 noreply 地址代替可联系邮箱。
- 确认对自有代码和提示词具有 MIT 授权权利。
- 确认 GitHub 多因素认证状态；获准使用 SignPath 时也需启用多因素认证。
- 如实说明尚无 GitHub Release、远程 CI 和签名集成；main 分支源码不等于已发布所需形式的签名产物。
- 官方条款对项目信誉、已发布产物及削弱安全措施的功能有限制，应先询问适用性，不保证此候选版符合要求。
- 当前工具只能读取申请页面的静态内容，不能操作嵌入表单；维护者需在 https://signpath.org/apply 填写并提交，或在具备浏览器操作能力的环境继续。

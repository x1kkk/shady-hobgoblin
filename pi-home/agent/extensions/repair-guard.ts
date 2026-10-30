// ============================================================
// Pi Agent - repair-guard 权限门扩展  v2
//
// 硬性条件（本工具不可关闭）：
//   1) 任何“删除类”操作 -> 强制二次确认（ctx.ui.confirm）
//   2) 涉及数据文件 / 用户目录 -> 确认对话框必须列出文件类型与目录（更强提示）
//   3) 非交互模式（-p / JSON）-> 删除类操作一律拒绝（fail-closed）
//   4) 不可确认的高危操作（格式化/diskpart clean/删除卷影等）-> 直接禁止
//   5) 其它危险操作 -> 弹窗确认
//
// 日志: <U盘>\logs\pi_actions.log
// ============================================================
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

type Rule = { re: RegExp; label: string };

// ---------- 直接禁止（不可确认）----------
const BLOCKED: Rule[] = [
  { re: /\bformat\s+[a-z]:/i, label: "format 磁盘" },
  { re: /\bdiskpart\b[\s\S]*\bclean\b/i, label: "diskpart clean" },
  { re: /\brd\s+\/s\s+\/q\s+(c:|%systemdrive%)/i, label: "删除系统盘" },
  { re: /\bdel\s+\/s\s+\/q\s+(c:\\windows|c:\\system32)/i, label: "删除系统目录" },
  { re: /\brm\s+-rf\s+\//i, label: "rm -rf /" },
  { re: /\b(vssadmin|wmic)\b[\s\S]*\bshadow(copy)?\b[\s\S]*\bdelete\b/i, label: "删除卷影副本" },
  { re: /\bcipher\s+\/w\b/i, label: "擦除空闲空间" },
];

// ---------- 删除类操作（必须二次确认）----------
const DELETE_RULES: Rule[] = [
  { re: /\bRemove-Item\b/i, label: "Remove-Item" },
  { re: /\bRemove-ItemProperty\b/i, label: "Remove-ItemProperty" },
  { re: /\bClear-Content\b/i, label: "Clear-Content（清空文件内容）" },
  { re: /\bClear-RecycleBin\b/i, label: "清空回收站" },
  { re: /\b(Remove-Partition|Clear-Disk|Initialize-Disk|Format-Volume)\b/i, label: "磁盘级删除/格式化" },
  { re: /\b(rd|rmdir)\s+\/s\b/i, label: "rd /s" },
  { re: /(^|[\s;&|])(del|erase)\s+\S/i, label: "del / erase" },
  { re: /\breg\s+delete\b/i, label: "reg delete" },
  { re: /\bsc(\.exe)?\s+delete\b/i, label: "sc delete" },
  { re: /\bschtasks\b[\s\S]*\/delete\b/i, label: "schtasks /delete" },
  { re: /\bwmic\b[\s\S]*\bdelete\b/i, label: "wmic delete" },
  { re: /\brm\s+-[a-z]*[rf]/i, label: "rm -rf" },
  { re: /\brsync\b[\s\S]*--delete/i, label: "rsync --delete" },
  { re: /\bfind\b[\s\S]*\s-delete\b/i, label: "find -delete" },
  { re: /\bgit\s+(clean\s+-[a-z]*[fd]|reset\s+--hard)/i, label: "git 丢弃本地改动" },
  { re: /\brobocopy\b[\s\S]*\/(MIR|PURGE|MOV|MOVE)\b/i, label: "robocopy 镜像/移动（会删除目标端多余文件）" },
  { re: /\bMove-Item\b/i, label: "Move-Item（源位置数据消失）" },
  { re: /\bTruncate\b|\bSet-Content\b[\s\S]*-Value\s*\$null/i, label: "截断/清空文件" },
];

// ---------- 其它危险操作（需确认，但不属于删除）----------
const CONFIRM_RULES: Rule[] = [
  { re: /\breg\s+(add|import)\b/i, label: "修改注册表" },
  { re: /\bSet-ItemProperty\b/i, label: "修改注册表项/属性" },
  { re: /\bbcdedit\s+\/(set|delete|import)/i, label: "修改启动配置" },
  { re: /\bbootrec\b/i, label: "修复启动记录" },
  { re: /\bsfc\s+\/scannow\b/i, label: "SFC 系统文件修复" },
  { re: /\bdism\s+\/online\s+\/cleanup-image\s+\/restorehealth\b/i, label: "DISM 组件修复" },
  { re: /\bnetsh\s+\w+\s+reset\b/i, label: "重置网络栈" },
  { re: /\bnetsh\s+advfirewall\s+(set|reset)\b/i, label: "修改防火墙" },
  { re: /\bsc\s+(stop|config)\b/i, label: "停止/配置服务" },
  { re: /\bnet\s+stop\b/i, label: "停止服务" },
  { re: /\bchkdsk\s+[a-z]:\s+\/f\b/i, label: "chkdsk /f 修复磁盘" },
  { re: /\bipconfig\s+\/release\b/i, label: "释放 IP" },
  { re: /\bfix\.ps1\b/i, label: '执行修复脚本（会修改系统，需人工确认）' },
  { re: /\bshutdown\s+\/r\b/i, label: "重启计算机" },
  { re: /fix\.ps1/i, label: "执行修复脚本（会修改系统，需人工确认）" },
];

// ---------- 数据文件 / 用户目录特征 ----------
const DATA_EXT = /\.(docx?|xlsx?|pptx?|pdf|rtf|wps|et|dps|md|txt|csv|json|xml|ini|reg|bak|db|sqlite|mdb|accdb|pst|ost|eml|msg|jpg|jpeg|png|gif|bmp|heic|tif|raw|mp4|mov|avi|mkv|wmv|mp3|wav|flac|aac|zip|rar|7z|tar|gz|iso|vhd|vhdx|key|pem|p12|pfx)\b/gi;
const USER_DIR = /(桌面|Desktop|文档|Documents|图片|Pictures|视频|Videos|音乐|Music|下载|Downloads|OneDrive|WeChat Files|微信|QQ|Tencent|WPS|钉钉|企业微信|xwechat)/i;

const DATA_EXAMPLE = "文档 doc/docx/xls/xlsx/ppt/pptx/pdf、图片、音视频、压缩包、数据库、邮件、密钥";

export default function (pi: ExtensionAPI) {
  const root = (() => {
    const home = process.env.PI_CODING_AGENT_DIR || "";
    return home ? join(home, "..", "..") : process.cwd();
  })();
  const logDir = join(root, "logs");
  const logFile = join(logDir, "pi_actions.log");

  function log(tag: string, message: string) {
    try {
      if (!existsSync(logDir)) mkdirSync(logDir, { recursive: true });
      // Commands and UI messages can contain passwords, tokens, private paths or customer data.
      // Record the event category only; never persist the raw command or confirmation payload.
      appendFileSync(logFile, `${new Date().toISOString()} | ${tag}\n`, "utf8");
    } catch {
      /* 日志失败不阻断 */
    }
  }

  pi.on("tool_call", async (event, ctx) => {
    const name: string = event.toolName;
    const input: any = event.input ?? {};
    const cmd: string = String(input.command ?? input.args ?? input.script ?? "");
    if (!cmd) return;

    log("TOOL", `${name} | ${cmd}`);
    if (name !== "powershell" && name !== "bash") return;

    // 1) 硬禁止
    const blocked = BLOCKED.find((r) => r.re.test(cmd));
    if (blocked) {
      log("BLOCK", `${blocked.label} | ${cmd}`);
      return { block: true, reason: `维修安全策略禁止该操作：${blocked.label}（不可确认执行，请由人工评估）` };
    }

    // 2) 删除类操作 -> 强制二次确认
    const del = DELETE_RULES.find((r) => r.re.test(cmd));
    if (del) {
      const extHits = [...new Set((cmd.match(DATA_EXT) || []).map((s) => s.toLowerCase()))];
      const dirHit = cmd.match(USER_DIR);
      const isData = extHits.length > 0 || !!dirHit;

      // 非交互模式（-p / JSON / 无 UI）：一律拒绝，绝不默认放行
      if (!ctx.isInteractive) {
        log("DELETE-BLOCK", `非交互模式拒绝删除 | ${del.label} | ${cmd}`);
        return {
          block: true,
          reason:
            "删除操作必须在交互终端中由人工二次确认；当前为非交互模式（-p/JSON），已拒绝。请改为在 Pi 交互界面中操作，或由技术人员手工执行。",
        };
      }

      const lines = [
        `操作类型：${del.label}`,
        `命令：${cmd}`,
        isData && extHits.length ? `涉及数据文件类型：${extHits.join(", ")}` : "",
        isData && dirHit ? `涉及用户目录：${dirHit[0]}` : "",
        "该操作不可撤销，删除后无法恢复。",
        isData ? `注意：检测到可能涉及用户数据（${DATA_EXAMPLE}）。` : "",
        "如确需删除，请先确认已在 backups\\ 做过备份。",
      ].filter(Boolean);

      const title = isData ? "⛔ 删除用户数据 —— 二次确认" : "⚠️ 删除操作 —— 二次确认";
      const ok = await ctx.ui.confirm(title, lines.join("\n"));
      log("DELETE-CONFIRM", `${ok ? "同意" : "拒绝"} | ${del.label} | ${isData ? "DATA" : "normal"} | ${cmd}`);
      if (!ok) {
        return { block: true, reason: "用户在二次确认中拒绝该删除操作（delete-gate）" };
      }
      return;
    }

    // 3) 其它危险操作 -> 确认
    const conf = CONFIRM_RULES.find((r) => r.re.test(cmd));
    if (conf) {
      if (!ctx.isInteractive) {
        log("CONFIRM-BLOCK", `非交互模式拒绝 | ${conf.label}`);
        return { block: true, reason: `该操作需要人工确认（${conf.label}），非交互模式下已拒绝。` };
      }
      const ok = await ctx.ui.confirm("⚠️ 危险操作确认", [`操作类型：${conf.label}`, `命令：${cmd}`, "是否允许？"].join("\n"));
      log("CONFIRM", `${ok ? "同意" : "拒绝"} | ${conf.label}`);
      if (!ok) return { block: true, reason: "用户拒绝了危险操作" };
    }
    return;
  });
}

import React from "react";
import { Button, PromptBlock, Tag } from "designonline-ui";
import { useT } from "../lang.jsx";
import { SecHead } from "./SecHead.jsx";

const INSTALL_CMD =
  "git clone https://github.com/EarthOnlineLabs/claude-gauge.git\ncd claude-gauge && ./install.sh";

const UNINSTALL_CMD = "~/.claude/claude-gauge-uninstall.sh";

const PKG_URL =
  "https://github.com/EarthOnlineLabs/claude-gauge/releases/latest/download/ClaudeGauge.pkg";

export function Install() {
  const { t } = useT();
  const STEPS = [
    t("Installs SwiftBar via Homebrew", "用 Homebrew 装好 SwiftBar"),
    t("Loads a 30s background refresher", "加载一个 30 秒后台刷新器"),
    t("Pulls your first reading", "拉取你的第一份读数"),
  ];
  return (
    <section id="install" className="cg-section">
      <div className="cg-shell">
        <SecHead
          eyebrow={t("Get it running", "让它跑起来")}
          title={t("Pick your way in", "选一种装法")}
          lede={t(
            "Download the installer and double-click, or clone the repo and run the script. Both do the same thing.",
            "下载安装包双击安装，或克隆仓库跑脚本。两种方式效果一样。"
          )}
        />
        <div className="cg-install">
          {/* --- .pkg download --- */}
          <a className="cg-pkg-btn" href={PKG_URL} download>
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">
              <path d="M10 3v10m0 0l-3.5-3.5M10 13l3.5-3.5M4 15.5h12" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
            <span className="cg-pkg-btn__label">
              {t("Download installer", "下载安装包")}
              <small>.pkg</small>
            </span>
          </a>

          <p className="cg-or">{t("or, in Terminal", "或者用终端")}</p>

          {/* --- terminal install --- */}
          <PromptBlock className="cg-code" code={INSTALL_CMD} copyLabel={t("Copy", "复制")} copiedLabel={t("Copied", "已复制")}>
            <span className="cg-c-cmd">git clone</span> https://github.com/EarthOnlineLabs/claude-gauge.git<br />
            <span className="cg-c-cmd">cd</span> claude-gauge && ./install.sh
          </PromptBlock>

          <div className="cg-install__side">
            <div className="cg-stepchips">
              {STEPS.map((s, i) => <Tag key={i} className="cg-stepchip"><b>{i + 1}.</b> {s}</Tag>)}
            </div>
            <p className="cg-note">
              {t("Needs macOS, a signed-in Claude Code with a Pro/Max subscription, and system ", "需要 macOS、已登录且拥有 Pro/Max 订阅的 Claude Code，以及系统自带的 ")}<code className="cg-code-i">python3</code>
              {t(". Optional: point Claude Code's ", "。可选：把 Claude Code 的 ")}<code className="cg-code-i">statusLine</code>
              {t(" at the bridge for zero-cost instant updates while you work. Removing it later leaves your Claude Code credentials and data completely untouched.", " 指向桥接脚本，干活时零成本即时刷新。日后卸载，绝不动你的 Claude Code 凭证和数据。")}
            </p>
          </div>

          {/* --- uninstall (separate, secondary) --- */}
          <div className="cg-uninstall">
            <p className="cg-uninstall__label">{t("Uninstall anytime — credentials stay untouched", "随时卸载 —— 绝不动你的凭证")}</p>
            <PromptBlock className="cg-code cg-code--sm" code={UNINSTALL_CMD} copyLabel={t("Copy", "复制")} copiedLabel={t("Copied", "已复制")}>
              <span className="cg-c-cmd">~/.claude/claude-gauge-uninstall.sh</span>
            </PromptBlock>
          </div>
        </div>
      </div>
    </section>
  );
}

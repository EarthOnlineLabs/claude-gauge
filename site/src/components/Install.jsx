import React from "react";
import { PromptBlock, Tag } from "designonline-ui";
import { useT } from "../lang.jsx";
import { SecHead } from "./SecHead.jsx";

// 复制用的干净纯文本（与下面带高亮的展示文本不同）。
const COPY_CMD =
  "git clone https://github.com/EarthOnlineLabs/claude-gauge.git\ncd claude-gauge && ./install.sh\n\n./uninstall.sh";

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
          title={t("Two commands and you're done", "两条命令就搞定")}
          lede={t("Clone the repo and run the installer. It handles SwiftBar, the background refresher, and the first data pull.", "克隆仓库，运行安装脚本。SwiftBar、后台刷新器和首次拉取数据，它全包了。")}
        />
        <div className="cg-install">
          <PromptBlock className="cg-code" code={COPY_CMD} copyLabel={t("Copy", "复制")} copiedLabel={t("Copied", "已复制")}>
            <span className="cg-c-cmt"># {t("clone and install — macOS only", "克隆并安装 —— 仅限 macOS")}</span><br />
            <span className="cg-c-cmd">git clone</span> https://github.com/EarthOnlineLabs/claude-gauge.git<br />
            <span className="cg-c-cmd">cd</span> claude-gauge && ./install.sh<br /><br />
            <span className="cg-c-cmt"># {t("remove anytime — credentials stay untouched", "随时卸载 —— 绝不动你的凭证")}</span><br />
            <span className="cg-c-cmd">./uninstall.sh</span>
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
        </div>
      </div>
    </section>
  );
}

import React from "react";
import { useT } from "../lang.jsx";
import { BrandMark, EOMark } from "../visuals/gauge.jsx";

const REPO = "https://github.com/EarthOnlineLabs/claude-gauge";

export function Footer() {
  const { t } = useT();
  return (
    <footer className="cg-footer">
      <div className="cg-shell">
        <div className="cg-foot-brand"><BrandMark size={20} /></div>
        <p className="cg-foot-meta">
          <a href={REPO} target="_blank" rel="noreferrer">GitHub</a> · {t("MIT License", "MIT 许可证")} · {t("built by ", "由 ")}
          <EOMark /> <a href="https://github.com/EarthOnlineLabs" target="_blank" rel="noreferrer">EarthOnline Labs</a>{t("", " 打造")}<br />
          {t("ClaudeGauge is an independent tool and is not affiliated with Anthropic.", "ClaudeGauge 是独立工具，与 Anthropic 无任何关联。")}
        </p>
        <p className="cg-foot-fine">
          {t("A note on this page: it uses cookieless, first-party analytics — no third-party trackers, no cookies. The ClaudeGauge app itself still sends nothing to anyone; it reads only your official usage, never your conversations or code.", "关于本页：它使用无 cookie 的第一方统计——没有第三方追踪，也没有 cookie。ClaudeGauge 工具本身依旧不向任何人发送数据：只读你的官方用量，绝不读你的对话或代码。")}
        </p>
      </div>
    </footer>
  );
}

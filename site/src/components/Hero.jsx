import React from "react";
import { Button } from "designonline-ui";
import { useT } from "../lang.jsx";
import { InkDial, GitHubIcon } from "../visuals/gauge.jsx";
import { HeroLive } from "./HeroLive.jsx";

const REPO = "https://github.com/EarthOnlineLabs/claude-gauge";

export function Hero() {
  const { t } = useT();
  const CHECKS = [t("Tiny", "小巧"), t("Private", "安全"), t("Zero quota cost", "零额度消耗"), t("Free & open source", "免费开源")];
  return (
    <header className="cg-hero" id="top">
      <div className="cg-shell">
        <h1 className="cg-hero__title">
          {t("Your Claude Code usage,", "你的 Claude Code 用量，")}<br />
          <span className="cg-hero__accent">{t("live in the menu bar.", "常驻菜单栏。")}</span>
        </h1>
        <div className="cg-checks">
          {CHECKS.map((c, i) => (
            <span key={i} className="cg-check"><span className="cg-check__mk">✓</span>{c}</span>
          ))}
        </div>
        <div className="cg-hero__cta">
          <Button variant="primary" size="lg" icon={<InkDial s={18} />} onClick={() => location.assign("#install")}>
            {t("Get started", "开始使用")}
          </Button>
          <Button variant="secondary" size="lg" icon={<GitHubIcon s={16} />} onClick={() => window.open(REPO, "_blank")}>
            {t("View on GitHub", "在 GitHub 上查看")}
          </Button>
        </div>
        <HeroLive />
      </div>
    </header>
  );
}

import React from "react";
import { Button } from "designonline-ui";
import { useT } from "../lang.jsx";
import { BrandMark, GitHubIcon, InkDial } from "../visuals/gauge.jsx";

const REPO = "https://github.com/EarthOnlineLabs/claude-gauge";

export function Header() {
  const { t, toggle } = useT();
  return (
    <header className="cg-header">
      <div className="cg-shell cg-header__bar">
        <a className="cg-brandlink" href="#top" aria-label="ClaudeGauge"><BrandMark size={22} /></a>
        <div className="cg-header__actions">
          <a className="cg-nav-ghost" href={REPO} target="_blank" rel="noreferrer"><GitHubIcon s={15} /> <span>GitHub</span></a>
          <Button variant="primary" size="sm" icon={<InkDial s={16} />} onClick={() => location.assign("#install")}>
            {t("Install", "安装")}
          </Button>
          <button className="cg-lang" onClick={toggle} aria-label="Switch language">{t("中文", "EN")}</button>
        </div>
      </div>
    </header>
  );
}

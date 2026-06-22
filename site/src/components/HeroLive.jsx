import React from "react";
import { Segmented } from "designonline-ui";
import { useT } from "../lang.jsx";
import { GaugePill, UsageDropdown, SysIcons, AppleMark } from "../visuals/gauge.jsx";

/* Hero 内的交互式菜单栏预览：点药丸展开/收起下拉；Segmented 切 5 态。默认「留意」且展开。 */
export function HeroLive() {
  const { t, lang } = useT();
  const STATES = {
    ok: {
      label: t("Plenty", "充裕"), pill: { text: "49%", state: "ok" },
      rows: [{ kind: "session", pct: 49, left: 51, reset: "2h41m", state: "ok" }, { kind: "week", pct: 63, left: 37, reset: "4d", state: "ok" }],
    },
    warn: {
      label: t("Heads up", "留意"), pill: { text: "82% 38m", state: "warn" },
      rows: [{ kind: "session", pct: 82, left: 18, reset: "38m", state: "warn" }, { kind: "week", pct: 41, left: 59, reset: "5d", state: "ok" }],
    },
    crit: {
      label: t("Critical", "告急"), pill: { text: "W93% 2d", state: "crit" },
      rows: [{ kind: "session", pct: 58, left: 42, reset: "1h20m", state: "ok" }, { kind: "week", pct: 93, left: 7, reset: "2d", state: "crit" }],
    },
    done: {
      label: t("Done", "完成提醒"), pill: { text: "31%", state: "ok", rainbow: true, pulse: true },
      rows: [{ kind: "session", pct: 31, left: 69, reset: "3h05m", state: "ok" }, { kind: "week", pct: 50, left: 50, reset: "4d", state: "ok" }],
    },
  };
  const ORDER = ["ok", "warn", "crit", "done"];
  const MENUS = [t("File", "文件"), t("Edit", "编辑"), t("View", "显示"), t("Window", "窗口"), t("Help", "帮助")];
  const [stKey, setStKey] = React.useState("warn");
  const [open, setOpen] = React.useState(true);
  const st = STATES[stKey];

  return (
    <div className="cg-herolive cg-rise">
      <div className="cg-live-desktop">
        <div className="cg-live-bar">
          <span className="cg-mb-left">
            <AppleMark />
            <b>Claude Code</b>{MENUS.map((m, i) => <span key={i}>{m}</span>)}
          </span>
          <span className="cg-mb-right">
            <span className="cg-pill-anchor">
              <button type="button" className="cg-live-pillbtn" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
                <GaugePill {...st.pill} lit={open} />
              </button>
              {open && <div className="cg-pop"><UsageDropdown lang={lang} rows={st.rows} /></div>}
            </span>
            <SysIcons />
            <span className="cg-clock">{t("Sat 21:04", "周六 21:04")}</span>
          </span>
        </div>
        <div className="cg-live-canvas" />
      </div>
      <div className="cg-live-controls">
        <span className="cg-live-ctl-label">{t("State", "状态")}</span>
        <Segmented
          options={ORDER.map((k) => ({ value: k, label: STATES[k].label }))}
          value={stKey}
          onChange={(k) => { setStKey(k); setOpen(true); }}
          aria-label={t("Switch state", "状态切换")}
        />
      </div>
    </div>
  );
}

import React from "react";
import { Meter } from "designonline-ui";

/* ============================================================================
   ClaudeGauge · 产品自绘视觉（非 DesignOnline 组件）
   全部用 DS token 自绘：表盘标记 / 字标 / 系统图标 / 菜单栏药丸 / 双语下拉。
   下拉里的进度条 = DS <Meter>。彩虹 = 五段光谱（仅识别），颜色零硬编码。
   移植自交接包 reference/gauge-visuals.jsx。
   ========================================================================== */

const cx = (...p) => p.filter(Boolean).join(" ");
const tt = (lang, en, zh) => (lang === "en" ? en : zh);

/* 表盘标记 — 半圆刻度 + 指针。rainbow=光谱(身份)；state=ok/warn/crit。 */
export function GaugeMark({ size = 20, rainbow = false, state = "ok", className }) {
  const stroke = rainbow ? "url(#cgRainbowStroke)" : "currentColor";
  const tone = state === "warn" ? "cg-tone-warn" : state === "crit" ? "cg-tone-danger" : "";
  return (
    <svg className={cx("cg-mark", tone, className)} width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true">
      {rainbow && (
        <defs>
          <linearGradient id="cgRainbowStroke" x1="2" y1="0" x2="22" y2="0" gradientUnits="userSpaceOnUse">
            <stop offset="0" style={{ stopColor: "var(--purple-500)" }} />
            <stop offset="0.28" style={{ stopColor: "var(--blue-500)" }} />
            <stop offset="0.55" style={{ stopColor: "var(--green-500)" }} />
            <stop offset="0.78" style={{ stopColor: "var(--orange-500)" }} />
            <stop offset="1" style={{ stopColor: "var(--coral-500)" }} />
          </linearGradient>
        </defs>
      )}
      <path d="M3.6 16.4a8.4 8.4 0 0 1 16.8 0" stroke={stroke} strokeWidth="2.2" strokeLinecap="round" />
      <path d="M12 16.4 16.6 10.6" stroke={stroke} strokeWidth="2.2" strokeLinecap="round" />
      <circle cx="12" cy="16.4" r="1.7" fill={stroke} />
    </svg>
  );
}

/* 品牌字标 ClaudeGauge */
export function BrandMark({ size = 22, className }) {
  return (
    <span className={cx("cg-brand", className)}>
      <GaugeMark size={size} rainbow />
      <span className="cg-brand__name">Claude<span className="cg-brand__g">Gauge</span></span>
    </span>
  );
}

/* 系统状态图标（电量 / wifi / 控制中心）— 衬托菜单栏 */
export function SysIcons() {
  return (
    <span className="cg-sys" aria-hidden="true">
      <svg width="22" height="13" viewBox="0 0 26 14" fill="none"><rect x="1" y="2.5" width="20" height="9" rx="2.6" stroke="currentColor" strokeWidth="1.3" /><rect x="2.8" y="4.3" width="13" height="5.4" rx="1.2" fill="currentColor" /><path d="M23.2 5v4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M4 11a12 12 0 0 1 16 0M7.5 14.5a7 7 0 0 1 9 0" /><circle cx="12" cy="18" r="1.1" fill="currentColor" stroke="none" /></svg>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="5.5" width="18" height="5.4" rx="2.7" /><rect x="3" y="13.1" width="18" height="5.4" rx="2.7" /></svg>
    </span>
  );
}

/* Apple 菜单图标 */
export function AppleMark() {
  return (
    <svg className="cg-apple" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.05 12.7c-.03-2.4 1.96-3.55 2.05-3.6-1.12-1.64-2.86-1.86-3.48-1.89-1.48-.15-2.89.87-3.64.87-.75 0-1.91-.85-3.14-.83-1.62.02-3.11.94-3.94 2.39-1.68 2.92-.43 7.24 1.2 9.61.8 1.16 1.75 2.46 3 2.41 1.2-.05 1.66-.78 3.11-.78 1.45 0 1.86.78 3.14.75 1.3-.02 2.12-1.18 2.91-2.35.92-1.35 1.3-2.66 1.32-2.73-.03-.01-2.53-.97-2.56-3.85zM14.7 5.6c.66-.8 1.1-1.92.98-3.03-.95.04-2.1.63-2.78 1.43-.61.71-1.14 1.84-1 2.93 1.06.08 2.14-.54 2.8-1.33z" /></svg>
  );
}

/* GitHub 标记 */
export function GitHubIcon({ s = 16 }) {
  return (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38v-1.34c-2.23.49-2.7-1.07-2.7-1.07-.36-.93-.89-1.18-.89-1.18-.73-.5.05-.49.05-.49.81.06 1.23.83 1.23.83.72 1.23 1.88.87 2.34.67.07-.52.28-.87.5-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.01.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.03 2.2-.82 2.2-.82.44 1.11.16 1.92.08 2.12.51.56.82 1.28.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 0 0 16 8c0-4.42-3.58-8-8-8Z" /></svg>
  );
}

/* 墨色表盘（按钮图标用） */
export const InkDial = ({ s = 18 }) => <GaugeMark size={s} state="ok" />;

/* 菜单栏药丸 — 表盘 + 文本。stale=数据过期变灰；pulse=完成提醒彩虹脉冲发光。 */
export function GaugePill({ text = "49%", state = "ok", rainbow = false, lit = true, stale = false, pulse = false }) {
  return (
    <span className={cx("cg-pill", state !== "ok" && `cg-pill--${state}`, lit && "cg-pill--lit", stale && "cg-stale", pulse && "cg-pill--pulse")}>
      <GaugeMark size={15} rainbow={rainbow} state={stale ? "ok" : state} />
      <span>{text}</span>
    </span>
  );
}

function ClockIcon() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="15" height="15"><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>;
}
function WeekIcon() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="15" height="15"><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M3 9h18M8 3v4M16 3v4" /></svg>;
}

/* 下拉明细行 — 进度条用 DS <Meter pct state>。 */
function DDRow({ lang, kind, pct, left, reset, state }) {
  return (
    <div className="cg-dd-row">
      <div className="cg-dd-label">
        {kind === "week" ? <WeekIcon /> : <ClockIcon />}
        <span>{kind === "week" ? tt(lang, "This week · 7-day", "本周 · 7 天") : tt(lang, "Current 5-hour · session", "当前 5 小时 · 会话")}</span>
      </div>
      <div className={cx("cg-dd-used", state !== "ok" && `cg-dd-used--${state}`)}>
        <b>{pct}%</b><span className="cg-dd-muted"> {tt(lang, "used", "已用")} · {left}% {tt(lang, "left", "还剩")}</span>
      </div>
      <Meter pct={pct} state={state} />
      <div className="cg-dd-reset">{tt(lang, "resets in " + reset, reset + " 后重置")}</div>
    </div>
  );
}

/* 下拉明细卡 */
export function UsageDropdown({ lang = "zh", rows, foot = true }) {
  return (
    <div className="cg-dropdown">
      <div className="cg-dd-head"><GaugeMark size={16} rainbow /> <span>{tt(lang, "Claude Code usage", "Claude Code 用量")}</span></div>
      {rows.map((r, i) => <DDRow key={i} lang={lang} {...r} />)}
      {foot && (
        <div className="cg-dd-foot">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 12a9 9 0 1 1-3-6.7M21 3v6h-6" /></svg>
          <span>{tt(lang, "Updated 21:04 (just now) · refresh now", "更新于 21:04（刚刚）· 立即刷新")}</span>
        </div>
      )}
    </div>
  );
}

/* 页脚 EarthOnline Labs ∞ 字标（五段光谱，仅识别） */
export function EOMark() {
  return (
    <svg className="cg-eo" width="34" height="19" viewBox="0 0 100 56" aria-label="EarthOnline Labs">
      <defs>
        <linearGradient id="cgEo" x1="16" y1="0" x2="84" y2="0" gradientUnits="userSpaceOnUse">
          <stop offset="0" style={{ stopColor: "var(--purple-500)" }} /><stop offset=".25" style={{ stopColor: "var(--blue-500)" }} />
          <stop offset=".5" style={{ stopColor: "var(--green-500)" }} /><stop offset=".75" style={{ stopColor: "var(--orange-500)" }} />
          <stop offset="1" style={{ stopColor: "var(--coral-500)" }} />
        </linearGradient>
      </defs>
      <path d="M50 28 C 42 15, 18 15, 18 28 C 18 41, 42 41, 50 28 C 58 15, 82 15, 82 28 C 82 41, 58 41, 50 28 Z" fill="none" stroke="url(#cgEo)" strokeWidth="10" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

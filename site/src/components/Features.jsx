import React from "react";
import { Card, CardBody, CardTitle, CardText, Icon } from "designonline-ui";
import { useT } from "../lang.jsx";
import { SecHead } from "./SecHead.jsx";

export function Features() {
  const { t } = useT();
  // 图标全部用 DS <Icon>：observe / shield / coin / bolt（蓝图 shieldCheck → DS 正式名 shield）。
  const FEATS = [
    { icon: "observe", title: t("Glance and go", "一眼就懂"), text: t("A quiet number when you have room; amber then red with a countdown as quota runs low. Notch-friendly, always out of your way.", "宽裕时是个安静的数字，吃紧了自己变橙变红、带上倒计时。刘海友好，从不挡道。") },
    { icon: "shield", title: t("Never lies to you", "绝不骗你"), text: t("If the numbers go stale it fades to gray — never old data dressed up as live.", "数据过期就老实变灰，绝不拿旧数字伪装成实时。") },
    { icon: "coin", title: t("Costs you nothing", "零额度消耗"), text: t("Refreshes in the background and never spends a token of your subscription.", "后台静默刷新，永不花掉你订阅里的一个 token。") },
    { icon: "bolt", title: t("In and out in seconds", "装卸都利索"), text: t("A couple of commands to install, one to remove — uninstalling cleans up completely.", "几行命令装好，一行命令卸净，卸载清得干干净净。") },
  ];
  return (
    <section id="features" className="cg-section cg-band">
      <div className="cg-shell">
        <SecHead
          eyebrow={t("A featherweight tool", "轻量小工具")}
          title={t("Small, honest, and out of your way", "小巧、诚实、不挡道")}
          lede={t("It only speaks up when it matters — and only ever tells the truth.", "只在要紧时出声，而且只说实话。")}
        />
        <div className="cg-grid cg-grid--4 cg-feats">
          {FEATS.map((f, i) => (
            <Card key={i} interactive className="cg-feature">
              <CardBody>
                <span className="cg-card-icon"><Icon name={f.icon} size={24} /></span>
                <div className="cg-feature__tx">
                  <CardTitle>{f.title}</CardTitle>
                  <CardText>{f.text}</CardText>
                </div>
              </CardBody>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}

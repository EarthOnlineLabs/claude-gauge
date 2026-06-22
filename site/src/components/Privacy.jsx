import React from "react";
import { Card, CardBody, CardTitle, CardText, Icon } from "designonline-ui";
import { useT } from "../lang.jsx";
import { SecHead } from "./SecHead.jsx";

export function Privacy() {
  const { t } = useT();
  const ROWS = [
    { icon: "key", aura: "purple", title: t("Token-only access", "只取 token"), text: t("One keychain OAuth token, sent only to Anthropic to fetch usage.", "只读钥匙串里一个 OAuth token，只发往 Anthropic 拉用量。") },
    { icon: "code", aura: "blue", title: t("Open & auditable", "开源、能审"), text: t("Plain bash & Python — no minification, binaries, or telemetry.", "纯 bash + Python，不压缩、无二进制、零埋点。") },
    { icon: "license", aura: "coral", title: t("MIT licensed", "MIT 许可"), text: t("Use, fork, modify freely; uninstall leaves no trace.", "可自由使用、fork、修改，卸载不留痕。") },
  ];
  return (
    <section id="privacy" className="cg-section cg-band">
      <div className="cg-shell">
        <SecHead
          eyebrow={t("What it can and can't see", "它能看到什么，看不到什么")}
          title={t("Private by design", "绝对隐私安全")}
          lede={t("A glance at your usage doesn't need your conversations — so it never reads them.", "看额度根本用不着读你的对话，所以它不读。")}
        />
        <div className="cg-grid cg-grid--3 cg-priv-cards">
          {ROWS.map((r, i) => (
            <Card key={i} interactive className={`cg-priv-card aura aura--${r.aura}`}>
              <CardBody>
                <span className="cg-card-icon"><Icon name={r.icon} size={28} /></span>
                <CardTitle>{r.title}</CardTitle>
                <CardText>{r.text}</CardText>
              </CardBody>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}

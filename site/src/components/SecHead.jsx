import React from "react";

export function SecHead({ eyebrow, title, lede }) {
  return (
    <div className="cg-section__head">
      <span className="cg-kicker">{eyebrow}</span>
      <h2 className="cg-h2">{title}</h2>
      <p className="cg-lede">{lede}</p>
    </div>
  );
}

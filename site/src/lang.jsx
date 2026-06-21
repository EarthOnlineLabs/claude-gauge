import React from "react";

// 双语上下文：t(en, zh) 取当前语言文案；toggle 中⇄EN；写 localStorage["cg-lang"] + <html lang>。
const LangCtx = React.createContext({ lang: "zh", t: (_en, zh) => zh, toggle: () => {} });

export const useT = () => React.useContext(LangCtx);

export function LangProvider({ children }) {
  const [lang, setLang] = React.useState(() => {
    try {
      const s = localStorage.getItem("cg-lang");
      if (s === "en" || s === "zh") return s;
    } catch (e) {}
    return (navigator.language || "").toLowerCase().startsWith("zh") ? "zh" : "en";
  });

  React.useEffect(() => {
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    document.documentElement.dataset.lang = lang;
    try { localStorage.setItem("cg-lang", lang); } catch (e) {}
  }, [lang]);

  const value = {
    lang,
    t: (en, zh) => (lang === "en" ? en : zh),
    toggle: () => setLang((l) => (l === "zh" ? "en" : "zh")),
  };
  return <LangCtx.Provider value={value}>{children}</LangCtx.Provider>;
}

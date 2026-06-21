import React from "react";
import { createRoot } from "react-dom/client";

// 顺序很重要：先 DS token + 组件样式（已剥离外部字体 @import），再自托管字体，最后页面布局层。
import "./styles/designonline-ui.generated.css";
import "./styles/fonts.css";
import "./styles/site.css";

import { App } from "./App.jsx";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

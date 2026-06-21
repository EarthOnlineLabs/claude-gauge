import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// 纯静态产物（dist/）。designonline-ui 本地打包进产物，无第三方运行时请求。
export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist", assetsDir: "assets", emptyOutDir: true },
});

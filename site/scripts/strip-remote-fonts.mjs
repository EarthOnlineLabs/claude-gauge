/* 把已安装的 designonline-ui/styles.css 复制成本地一份，并去掉其中 3 个外部字体
   @import（Google Fonts / cdnfonts / jsdelivr）。本站自托管同名字体（见 src/styles/fonts.css），
   以保持「无第三方运行时请求」。仅删外部 @import，绝不改任何组件样式（非 fork）。
   生成物 src/styles/designonline-ui.generated.css 已 gitignore，dev/build 前自动重生成。 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const src = resolve(root, "node_modules/designonline-ui/dist/styles.css");
const out = resolve(root, "src/styles/designonline-ui.generated.css");

let css = readFileSync(src, "utf8");
const before = css.match(/^@import\s+url\(["']?https?:\/\//gim)?.length || 0;
css = css.replace(/^@import\s+url\(["']?https?:\/\/[^)]*\)\s*;?[^\n]*$/gim, "");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, css, "utf8");
console.log(`✓ designonline-ui.generated.css 已生成（剥离 ${before} 条外部字体 @import）`);

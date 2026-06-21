#!/usr/bin/env bash
# 重新生成菜单栏图标的 base64（构建期一次性；产物内嵌在 plugin 的 ICON_* 常量里）。
#
# 形状来源 = 品牌 logo `docs/logo.svg`（分段光谱仪表盘，与落地页/favicon 同形），但**描边更细**：
# 品牌 logo 用粗描边(3.1)适合大尺寸 hero；菜单栏要与 Apple SF 符号同处一栏，必须**减重到 ~1.8**
# 才不显粗、和原生图标和谐（实测对比定的值，见 tasks/lessons.md）。形状一致、只是更细。
#
# 五态各渲一张 @2x PNG，紧裁到表盘外框，再 base64：
#   ICON_OK    单色蒙版（templateImage 用 alpha，自动随真实菜单栏深浅变黑/白）
#   ICON_WARN  橙 #C2902E   ICON_CRIT 红 #C0492B   ICON_STALE 灰 #9CA0A2  （= DesignOnline token 值）
#   ICON_RAINBOW 原样彩虹（紫→红硬分段 + 深针 + 白芯，= 落地页 logo 本体、按菜单栏重量减细）
#
# 实测（2026-06，当前 macOS + SwiftBar）：用干净矢量出图时 templateImage 与 image= 在菜单栏【均无框】，
# 与 sfimage 一样干净（详见 tasks/lessons.md L7/L9）。
#
# 依赖：仅构建期需要 `rsvg-convert`（`brew install librsvg`）。插件【运行期】只读内嵌 base64，零依赖。
# 用法：bash alert/build-menubar-icons.sh
#        → 把末尾打印的 5 个 base64 粘回 plugin/claude-gauge.15s.sh 的 ICON_OK/WARN/CRIT/STALE/RAINBOW。
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="docs/logo.svg"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
command -v rsvg-convert >/dev/null || { echo "需要 rsvg-convert：brew install librsvg" >&2; exit 1; }

# 紧裁视框（只框住表盘，留极小留白），与 plugin 里 ICON_SZ=width=21 height=17 等比
VB='1.5 1.6 21.0 17.4'

python3 - "$SRC" "$TMP" "$VB" <<'PY'
import sys
src_path, tmp, vb = sys.argv[1], sys.argv[2], sys.argv[3]
# 菜单栏重量（比品牌 logo 细，和 SF 符号和谐）：弧 1.8 / 针 1.44 / 轴 r1.48 / 白芯 r0.66
ARC_SW, NEEDLE_SW, HUB_R, PIP_R = "1.8", "1.44", "1.48", "0.66"
ARC = ["#8A43E6","#4FA8F0","#1FA45D","#F4811E","#E8482A"]

def base():
    s = open(src_path).read().replace('viewBox="0 0 24 24"', f'viewBox="{vb}"')
    s = s.replace('stroke-width="3.1"', f'stroke-width="{ARC_SW}"')                 # 弧描边减细
    s = s.replace('stroke="#1B1B1B" stroke-width="2.4"', f'stroke="#1B1B1B" stroke-width="{NEEDLE_SW}"')  # 针减细
    s = s.replace('<circle cx="12" cy="12" r="2.3" fill="#1B1B1B"/>', f'<circle cx="12" cy="12" r="{HUB_R}" fill="#1B1B1B"/>')  # 轴缩小
    s = s.replace('<circle cx="12" cy="12" r="0.85" fill="#FFFFFF"/>', f'<circle cx="12" cy="12" r="{PIP_R}" fill="#FFFFFF"/>')  # 白芯缩小
    return s

def solid(color):
    t = base()
    for h in ARC: t = t.replace(f'stroke="{h}"', f'stroke="{color}"')
    t = t.replace('stroke="#1B1B1B"', f'stroke="{color}"').replace('fill="#1B1B1B"', f'fill="{color}"')
    t = t.replace(f'<circle cx="12" cy="12" r="{PIP_R}" fill="#FFFFFF"/>', '')      # 单色态去白芯，实心轴
    return t

# 配色对齐 DesignOnline token：ink-900 / warning=amber-700 / danger=red-700 / 过期=text-subtle(ink-500)。
# 注：ic_ok 在插件里走 templateImage（只用 alpha 蒙版，RGB 被 macOS 丢弃），此色仅作记录。
open(f"{tmp}/ic_ok.svg","w").write(solid("#1B1B1B"))
open(f"{tmp}/ic_warn.svg","w").write(solid("#C2902E"))
open(f"{tmp}/ic_crit.svg","w").write(solid("#C0492B"))
open(f"{tmp}/ic_stale.svg","w").write(solid("#9CA0A2"))
open(f"{tmp}/ic_rain.svg","w").write(base())   # 彩虹弧 + 黑针 + 白芯（= 品牌 logo 本体）
PY

for n in ok warn crit stale rain; do
  rsvg-convert -h 40 "$TMP/ic_$n.svg" -o "$TMP/ic_$n.png"   # @2x（显示 21x17 逻辑点）
done

echo "=== 把下面 5 个常量粘回 plugin/claude-gauge.15s.sh ==="
for pair in OK:ok WARN:warn CRIT:crit STALE:stale RAINBOW:rain; do
  name="${pair%%:*}"; file="${pair##*:}"
  printf 'ICON_%s="%s"\n' "$name" "$(base64 < "$TMP/ic_$file.png" | tr -d '\n')"
done

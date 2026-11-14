#!/bin/bash
# Regenerate the SDDM greeter logo (omarchy/logo.png) from the omageeko wordmark used by the
# screensaver (omageeko submodule: packages/omageeko/overlay/share/branding/logo.txt). Each character cell is two
# square pixels stacked: █ both, ▀ top, ▄ bottom. Same colour as upstream's logo.png.
# Usage: packages/omageeko-sles/sddm/make-logo.sh   (needs python3 + ImageMagick)
set -euo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
txt="$here/../../../omageeko/packages/omageeko/overlay/share/branding/logo.txt"
out="$here/omarchy/logo.png"
scale=${SCALE:-8}
color=${COLOR:-#A8CD76}
pbm=$(mktemp --suffix=.pbm); trap 'rm -f "$pbm"' EXIT
python3 -I - "$txt" "$pbm" <<'EOF'
import sys
lines = [l.rstrip() for l in open(sys.argv[1], encoding="utf-8")]
while lines and not lines[-1]: lines.pop()
while lines and not lines[0]: lines.pop(0)
w = max(len(l) for l in lines)
cells = {"█": (1, 1), "▀": (1, 0), "▄": (0, 1)}
rows = []
for l in lines:
    l = l.ljust(w)
    rows.append([cells.get(c, (0, 0))[0] for c in l])
    rows.append([cells.get(c, (0, 0))[1] for c in l])
with open(sys.argv[2], "w") as f:
    f.write(f"P1\n{w} {len(rows)}\n")
    for r in rows: f.write(" ".join(map(str, r)) + "\n")
EOF
read -r _ w h < <(sed -n 2p "$pbm" | sed 's/^/x /')
magick "$pbm" -colorspace sRGB -type TrueColorAlpha -sample "$((w*scale))x$((h*scale))!" \
  -fill "$color" -opaque black -transparent white -strip PNG32:"$out"
echo "wrote $out ($((w*scale))x$((h*scale)))"

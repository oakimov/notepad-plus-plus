#!/usr/bin/env bash
# Regenerate packaging/AppIcon.icns (+ .png) from the stock Notepad++ icon.
# Source: PowerEditor/src/icons/npp.ico (IDI_M30ICON in Notepad_plus.rc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/../PowerEditor/src/icons/npp.ico"
OUT="$ROOT/packaging"
ICONSET="$OUT/AppIcon.iconset"

if [[ ! -f "$SRC" ]]; then
  echo "error: missing $SRC" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

python3 - "$SRC" "$ICONSET" "$OUT" <<'PY'
import sys
from pathlib import Path
from PIL import Image

src, iconset_s, out_s = sys.argv[1:4]
iconset = Path(iconset_s)
out = Path(out_s)
base = Image.open(src).convert("RGBA")
at2x = "@" + "2x.png"

def save(size: int, name: str) -> None:
    base.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name, format="PNG")

for size, name in [
    (16, "icon_16x16.png"),
    (32, "icon_16x16" + at2x),
    (32, "icon_32x32.png"),
    (64, "icon_32x32" + at2x),
    (128, "icon_128x128.png"),
    (256, "icon_128x128" + at2x),
    (256, "icon_256x256.png"),
    (512, "icon_256x256" + at2x),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512" + at2x),
]:
    save(size, name)

base.resize((256, 256), Image.Resampling.LANCZOS).save(out / "AppIcon.png", format="PNG")
print("wrote PNG + iconset")
PY

iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"
rm -rf "$ICONSET"

# Keep SPM resource in sync.
mkdir -p "$ROOT/NppMac/Sources/NppMac/Resources"
cp "$OUT/AppIcon.png" "$ROOT/NppMac/Sources/NppMac/Resources/AppIcon.png"

echo "done: $OUT/AppIcon.icns"

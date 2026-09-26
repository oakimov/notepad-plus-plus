#!/usr/bin/env bash
# Build Rust FFI (static) + Swift release binary, assemble dist/NppMac.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> cargo build -p npp-ffi --release"
CARGO_TARGET_DIR="$ROOT/target" cargo build -p npp-ffi --release --offline

# Keep Swift C header in sync with the crate.
cp "$ROOT/crates/npp-ffi/include/npp_ffi.h" \
  "$ROOT/NppMac/Sources/Cnpp_ffi/include/npp_ffi.h"

export NPP_FFI_LIB_DIR="$ROOT/target/release"
# Prefer static link: hide the dylib so the linker does not pick it over .a
DYLIB="$NPP_FFI_LIB_DIR/libnpp_ffi.dylib"
DYLIB_BAK=""
if [[ -f "$DYLIB" ]]; then
  DYLIB_BAK="$DYLIB.bak"
  mv "$DYLIB" "$DYLIB_BAK"
fi
restore_dylib() {
  if [[ -n "$DYLIB_BAK" && -f "$DYLIB_BAK" ]]; then
    mv "$DYLIB_BAK" "$DYLIB"
  fi
}
trap restore_dylib EXIT

echo "==> swift build -c release"
cd "$ROOT/NppMac"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/NppMac"
cd "$ROOT"

APP="$ROOT/dist/NppMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/NppMac"
chmod +x "$APP/Contents/MacOS/NppMac"

# Original Notepad++ application icon (from PowerEditor/src/icons/npp.ico).
if [[ -f "$ROOT/packaging/AppIcon.icns" ]]; then
  cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT/packaging/AppIcon.png" ]]; then
  cp "$ROOT/packaging/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
fi

# SPM resource bundle (if present) for any other packaged resources.
RES_BUNDLE="$(dirname "$BIN")/NppMac_NppMac.bundle"
if [[ -d "$RES_BUNDLE" ]]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi

# Stock language + styler models for keyword highlighting / colors at runtime.
LANGS="$ROOT/../PowerEditor/src/langs.model.xml"
if [[ -f "$LANGS" ]]; then
  cp "$LANGS" "$APP/Contents/Resources/langs.model.xml"
fi
STYLERS="$ROOT/../PowerEditor/src/stylers.model.xml"
if [[ -f "$STYLERS" ]]; then
  cp "$STYLERS" "$APP/Contents/Resources/stylers.model.xml"
fi

# Bundle a curated set of Notepad++ themes for Settings → Theme.
THEMES_SRC="$ROOT/../PowerEditor/installer/themes"
THEMES_DST="$APP/Contents/Resources/themes"
mkdir -p "$THEMES_DST"
for t in Monokai.xml Zenburn.xml Solarized.xml Solarized-light.xml Twilight.xml \
         "Deep Black.xml" Obsidian.xml Bespin.xml "DarkModeDefault.xml" khaki.xml; do
  if [[ -f "$THEMES_SRC/$t" ]]; then
    cp "$THEMES_SRC/$t" "$THEMES_DST/"
  fi
done

echo "==> built $APP"
echo "    open $APP"

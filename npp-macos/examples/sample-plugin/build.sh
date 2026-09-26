#!/usr/bin/env bash
# Build and install the HelloNppMac sample plugin.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
INC="$ROOT/../../crates/npp-plugin/include"
OUT="$ROOT/HelloNppMac.dylib"
DEST="${HOME}/Library/Application Support/NppMac/plugins/HelloNppMac"

clang -shared -fPIC -o "$OUT" "$ROOT/hello_plugin.c" -I "$INC"
mkdir -p "$DEST"
cp "$OUT" "$DEST/HelloNppMac.dylib"
echo "Installed $DEST/HelloNppMac.dylib"
echo "In NppMac: Plugins → Refresh Plugin List → Hello NppMac → Say Hello"

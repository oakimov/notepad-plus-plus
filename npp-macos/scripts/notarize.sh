#!/usr/bin/env bash
# Codesign + notarize dist/NppMac.app (requires Apple Developer credentials).
#
# Required env:
#   NPP_SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NPP_NOTARY_PROFILE  keychain profile from `xcrun notarytool store-credentials`
#
# Optional:
#   NPP_APP             path to .app (default: dist/NppMac.app relative to npp-macos/)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${NPP_APP:-$ROOT/dist/NppMac.app}"

if [[ -z "${NPP_SIGN_IDENTITY:-}" ]]; then
  echo "error: set NPP_SIGN_IDENTITY to a Developer ID Application identity" >&2
  echo "  example: export NPP_SIGN_IDENTITY=\"Developer ID Application: Name (TEAMID)\"" >&2
  exit 1
fi
if [[ -z "${NPP_NOTARY_PROFILE:-}" ]]; then
  echo "error: set NPP_NOTARY_PROFILE (notarytool keychain profile name)" >&2
  echo "  create with: xcrun notarytool store-credentials PROFILE --apple-id ... --team-id ... --password ..." >&2
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "error: app not found at $APP — run scripts/package-app.sh first" >&2
  exit 1
fi

echo "==> codesign (Hardened Runtime)"
codesign --force --deep --options runtime --timestamp \
  --sign "$NPP_SIGN_IDENTITY" \
  "$APP"

echo "==> verify signature"
codesign --verify --verbose=2 "$APP"

ZIP="$(mktemp -t NppMacXXXX).zip"
echo "==> zip for notarytool → $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> notarytool submit (profile=$NPP_NOTARY_PROFILE)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NPP_NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "==> staple"
xcrun stapler staple "$APP"

echo "==> spctl assess"
spctl --assess --type execute --verbose "$APP" || true

echo "done: $APP"

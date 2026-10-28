#!/bin/bash
# Build "ScreenBar.app" from the Swift package and sign it.
#   scripts/build-app.sh            -> build/ScreenBar.app
#   scripts/build-app.sh --install  -> also copy to ~/Applications and launch it
# Signed ad hoc by default, which is enough to run it on the Mac that built it. To sign with your own
# certificate and bundle ID instead:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" BUNDLE_ID=com.example.ScreenBar scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release
APP="build/ScreenBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ScreenBarMenu" "$APP/Contents/MacOS/ScreenBarMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -n "${BUNDLE_ID:-}" ]] && plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x ScreenBarMenu 2>/dev/null || true
  rm -rf "$HOME/Applications/ScreenBar.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/ScreenBar.app"
  echo "Installed to ~/Applications and launched"
fi

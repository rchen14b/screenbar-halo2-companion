#!/bin/bash
# Build "ScreenBar.app" from the Swift package and sign it ad hoc.
#   scripts/build-app.sh            -> build/ScreenBar.app
#   scripts/build-app.sh --install  -> also copy to ~/Applications and launch it
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/ScreenBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ScreenBarMenu" "$APP/Contents/MacOS/ScreenBarMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x ScreenBarMenu 2>/dev/null || true
  rm -rf "$HOME/Applications/ScreenBar.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/ScreenBar.app"
  echo "Installed to ~/Applications and launched"
fi

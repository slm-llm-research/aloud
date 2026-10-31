#!/bin/bash
# Builds InstructFlow.app (release) into app/build/ and signs it.
#
#   scripts/bundle.sh            # ad-hoc signature
#   SIGN_ID="Murmur Dev" scripts/bundle.sh   # a stable identity, so macOS keeps permissions across rebuilds
#
# Ad-hoc signing changes the app's identity on every build, so macOS asks for Accessibility /
# Input Monitoring again after each rebuild. A stable SIGN_ID avoids that (PLAN.md §12).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=.build/release
APP=build/InstructFlow.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/InstructFlow" "$APP/Contents/MacOS/InstructFlow"
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

VERSION=$(git -C .. describe --tags --always 2>/dev/null || echo "0.1.0")
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>ai.instructflow.InstructFlow</string>
  <key>CFBundleName</key><string>InstructFlow</string>
  <key>CFBundleExecutable</key><string>InstructFlow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>InstructFlow listens only while you hold Right Shift (or after you double-tap it) to turn your speech into text.</string>
</dict>
</plist>
PLIST

# Prefer the stable identity from scripts/make-signing-cert.sh (in its own keychain, unlocked here
# with its fixed password, so no prompts); fall back to ad-hoc.
KC="$HOME/Library/Keychains/murmur-signing.keychain-db"
KEYCHAIN_ARGS=()
if [ -z "${SIGN_ID:-}" ] && [ -f "$KC" ]; then
  security unlock-keychain -p "murmur-dev-signing" "$KC"
  # codesign only finds identities in keychains on the user search list; append ours (idempotent,
  # existing keychains are kept in their order).
  if ! security list-keychains -d user | grep -q "murmur-signing.keychain-db"; then
    CURRENT=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/" *$//')
    # shellcheck disable=SC2086
    security list-keychains -d user -s $CURRENT "$KC"
  fi
  if security find-identity -p codesigning "$KC" | grep -q "Murmur Dev Signing"; then
    SIGN_ID="Murmur Dev Signing"
    KEYCHAIN_ARGS=(--keychain "$KC")
  fi
fi
echo "Signing with: ${SIGN_ID:-ad-hoc (permissions reset on every rebuild)}"
codesign --force --deep --options runtime \
  --entitlements scripts/InstructFlow.entitlements \
  ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
  --sign "${SIGN_ID:--}" "$APP"
codesign --verify --verbose=1 "$APP"
echo "Built $APP"

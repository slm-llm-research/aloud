#!/bin/bash
# One-time: creates a self-signed code-signing identity "Aloud Dev Signing" in its OWN keychain
# (~/Library/Keychains/aloud-signing.keychain-db) with a fixed password that scripts/bundle.sh
# uses to unlock it. Nothing touches your login keychain, so macOS never asks for your password.
#
# Signing every build with the same identity lets macOS keep Aloud's Microphone / Accessibility /
# Input Monitoring permissions across rebuilds. The identity only signs Aloud on this Mac.
# Remove it with: security delete-keychain ~/Library/Keychains/aloud-signing.keychain-db
set -euo pipefail

NAME="Aloud Dev Signing"
KC="$HOME/Library/Keychains/aloud-signing.keychain-db"
# Not a secret: it only protects a self-signed, local-only signing key, and bundle.sh needs it.
KC_PASS="aloud-dev-signing"

if [ -f "$KC" ] && security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "\"$NAME\" already exists in $KC."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$KC" ] || security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KC"

/usr/bin/openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
  -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
/usr/bin/openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:aloud-local
security import "$TMP/id.p12" -k "$KC" -P aloud-local -T /usr/bin/codesign
# Lets codesign use the key without any prompt (needs this keychain's password, not yours).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null

echo
security find-identity -p codesigning "$KC" | grep "$NAME" && echo "Created \"$NAME\" in $KC."

#!/bin/bash
# One-time setup: create a local code-signing certificate ("Talky Self-Signed")
# in your login keychain.
#
# Why: Xcode builds this app ad-hoc, so its code identity changes on every build,
# which makes macOS forget the Microphone / Speech / Accessibility permission
# grants each time. reinstall.sh re-signs each build with this stable cert so you
# grant permissions ONCE and they stick. Each developer generates their own cert.
#
# Run once:  ./setup-cert.sh    then:  ./reinstall.sh --build

set -e
NAME="Talky Self-Signed"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "✓ '$NAME' already in your keychain. You're set — run ./reinstall.sh --build"
    exit 0
fi

TMP="$(mktemp -d)"
cat > "$TMP/cfg.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cfg.cnf" -sha256 >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:talky -name "$NAME" >/dev/null 2>&1
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P talky -A -T /usr/bin/codesign
rm -rf "$TMP"

echo "✓ Created '$NAME' in your login keychain."
echo "  Next:  ./reinstall.sh --build"

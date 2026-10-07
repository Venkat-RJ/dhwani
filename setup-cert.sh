#!/bin/bash
# Create a stable local signing identity. Grant private-key access to codesign.
set -euo pipefail
umask 077
NAME="Talky Self-Signed"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    if security find-identity -p codesigning | grep -F "\"$NAME\"" >/dev/null; then
        echo "'$NAME' already exists. Run ./reinstall.sh --build."
        exit 0
    fi
    echo "Certificate '$NAME' exists without a usable signing identity." >&2
    echo "Recover its private key before creating another certificate." >&2
    exit 1
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/talky-cert.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
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
openssl rand -hex 32 > "$TMP/passphrase"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cfg.cnf" -sha256 >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout "file:$TMP/passphrase" -name "$NAME" >/dev/null 2>&1
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$(cat "$TMP/passphrase")" -x -T /usr/bin/codesign

echo "Created '$NAME' in your login keychain."
echo "Next: ./reinstall.sh --build"

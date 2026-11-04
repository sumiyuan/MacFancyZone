#!/bin/bash
# One-time setup: creates a self-signed code-signing identity named
# "MacPowertools Local Signing" in the login keychain. Signing every build with
# the same certificate keeps the app's designated requirement stable, so the
# Accessibility grant survives rebuilds (ad-hoc signing would lose it).
set -euo pipefail

NAME="MacPowertools Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Use the system LibreSSL: its PKCS#12 output is what `security import` accepts.
OPENSSL=/usr/bin/openssl

# Matches untrusted identities too; codesign signs fine with an untrusted
# self-signed certificate, so no trust settings are required.
# Captured first: `grep -q` exiting early could SIGPIPE `security` under pipefail.
IDENTITIES="$(security find-identity -p codesigning)"
if grep -qF "\"$NAME\"" <<<"$IDENTITIES"; then
    echo "Signing identity \"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

P12_PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$P12_PASS"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign

# Note: `security add-trusted-cert` is intentionally not run. codesign accepts
# the untrusted identity, and the designated requirement it produces
# (`certificate leaf = H"..."`) pins the exact certificate without needing trust.

echo "Created signing identity \"$NAME\":"
security find-identity -p codesigning | grep -F "\"$NAME\""

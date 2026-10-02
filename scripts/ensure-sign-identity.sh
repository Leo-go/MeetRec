#!/bin/sh
set -eu

NAME="MeetRec Local"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  exit 0
fi

DIR="$HOME/Library/Application Support/MeetRec/signing"
mkdir -p "$DIR"
chmod 700 "$DIR"

if [ ! -f "$DIR/codesign.crt" ] || [ ! -f "$DIR/codesign.key" ]; then
  CONF="$DIR/codesign.conf"
  cat > "$CONF" << 'EOF'
[ req ]
distinguished_name = req_dn
x509_extensions = codesign_ext
prompt = no
[ req_dn ]
CN = MeetRec Local
[ codesign_ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
    -config "$CONF" \
    -keyout "$DIR/codesign.key" \
    -out "$DIR/codesign.crt"
  chmod 600 "$DIR/codesign.key"
fi

P12="$DIR/codesign.p12"
openssl pkcs12 -export \
  -inkey "$DIR/codesign.key" \
  -in "$DIR/codesign.crt" \
  -out "$P12" \
  -passout pass:meetrec
chmod 600 "$P12"

security import "$P12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P meetrec \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security add-trusted-cert -d -r trustRoot \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  "$DIR/codesign.crt"

security find-identity -v -p codesigning | grep -q "\"$NAME\""

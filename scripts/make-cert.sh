#!/usr/bin/env bash
#
# Creates the self-signed code signing identity that Flip is built with.
#
# TCC keys a privacy grant to the designated requirement, which for an ad-hoc
# signature is the code directory hash — different every build. A certificate
# pins it to the bundle ID instead, so the grants survive rebuilds. Without it
# every `make install` costs two trips through System Settings.
#
# Interactive, safe to re-run and to interrupt: it resumes from whichever step
# is missing. `make uncert` starts over.

set -euo pipefail

IDENTITY="${1:-Flip Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Homebrew's OpenSSL 3 writes a PKCS#12 the Security framework refuses with
# "MAC verification failed"; macOS's own LibreSSL writes the older format it
# reads. Hence the pinned path rather than PATH.
OPENSSL=/usr/bin/openssl

# Only protects the file for the few milliseconds it exists in a temp directory.
TRANSIT_PASSWORD=flip

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already present. Nothing to do."
    exit 0
fi

# An interrupted run can leave a certificate behind, or an untrusted one, which
# is not yet a valid identity. Either is reused: a second would leave codesign
# with an ambiguous name.
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> Reusing the certificate already in the login keychain"
    security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$WORK/cert.pem"
else
    echo "==> Generating a self-signed code signing certificate"
    "$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
        -subj "/CN=$IDENTITY" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

    "$OPENSSL" pkcs12 -export -out "$WORK/identity.p12" \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout "pass:$TRANSIT_PASSWORD"

    echo "==> Importing into the login keychain"
    # Scoped to codesign: with -A any process could sign as this identity, and
    # anything signed as dev.mxwnk.Flip inherits Flip's Accessibility grant.
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSIT_PASSWORD" \
        -T /usr/bin/codesign

    # Comfort only: without it macOS puts up a keychain dialog on the first
    # sign. The key does not reliably carry the certificate's label, so this
    # cannot be targeted precisely and may fail — "Always Allow" does the same.
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

echo "==> Trusting the certificate for code signing (macOS will ask to confirm)"
# Untrusted, the certificate imports fine but reports CSSMERR_TP_NOT_TRUSTED and
# never counts as a signing identity. Scoped to codeSign, so not TLS.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo
    echo "Done. '$IDENTITY' is ready to sign with. Next: make install"
else
    echo
    echo "The certificate is in the keychain but still not a valid signing" >&2
    echo "identity. Open Keychain Access, select '$IDENTITY' under login, and" >&2
    echo "set Trust > Code Signing to 'Always Trust'." >&2
    exit 1
fi

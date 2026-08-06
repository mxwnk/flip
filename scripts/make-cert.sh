#!/usr/bin/env bash
#
# Creates the self-signed code signing identity that Flip is built with.
#
# TCC keys a privacy grant to the app's designated requirement, which for an
# ad-hoc signature is the code directory hash — a value that changes with every
# single build. Signing against a certificate instead pins the requirement to the
# bundle identifier and this certificate, so Accessibility and Screen Recording
# stay granted across rebuilds. Without it, every `make install` costs two trips
# through System Settings.
#
# Interactive: macOS asks to confirm the trust setting at the end. Safe to re-run
# and safe to interrupt — it picks up from whichever step is missing rather than
# creating a second certificate. Use `make uncert` to start over.

set -euo pipefail

IDENTITY="${1:-Flip Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Homebrew's OpenSSL 3 writes a PKCS#12 that the Security framework refuses with
# "MAC verification failed". The LibreSSL that ships with macOS writes the older
# format it can read, so the path is pinned rather than taken from PATH.
OPENSSL=/usr/bin/openssl

# Only protects the file for the few milliseconds it exists in a temp directory.
TRANSIT_PASSWORD=flip

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already present. Nothing to do."
    exit 0
fi

# A certificate can be left behind by an interrupted run, or be present but
# untrusted, which is not a valid identity yet. Either way it is reused, because
# importing a second one would leave codesign with an ambiguous name to match.
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
    # Scoped to codesign on purpose. Importing with -A would let any process on
    # the machine sign as this identity, and anything signed as dev.mxwnk.Flip
    # inherits Flip's Accessibility grant.
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSIT_PASSWORD" \
        -T /usr/bin/codesign

    # Comfort only: without it macOS puts up a keychain dialog the first time
    # codesign touches the key. The private key does not reliably carry the
    # certificate's label, so this cannot be targeted precisely and is allowed to
    # fail — clicking "Always Allow" once has the same effect.
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

echo "==> Trusting the certificate for code signing (macOS will ask to confirm)"
# Without a trust setting the certificate imports fine but reports
# CSSMERR_TP_NOT_TRUSTED and never counts as a valid signing identity. Scoped to
# codeSign so it is not trusted for anything else, TLS included.
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

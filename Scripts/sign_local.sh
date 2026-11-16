#!/bin/bash
#
# Re-signs an installed build with a stable local code-signing identity.
#
# The CI artifact is ad-hoc signed, so its designated requirement is tied to
# the build's cdhash. macOS then treats every update as a new app and resets
# Accessibility / Input Monitoring permissions.
#
# This script creates (once) a self-signed code-signing certificate in a
# dedicated keychain and re-signs the app with it. The resulting designated
# requirement is based on the bundle identifier and certificate root, which
# stay stable across updates. TCC permissions therefore survive updates as
# long as every update is signed with the same keychain.
#
# Usage:
#   Scripts/sign_local.sh /Applications/whisky-yaagl.app
#
# Optional environment:
#   WHISKY_LOCAL_SIGNING_DIR       certificate/key directory
#   WHISKY_LOCAL_SIGNING_KEYCHAIN  keychain path
#   WHISKY_LOCAL_SIGNING_PASSWORD  keychain password
#
# Keep the keychain and the signing directory: replacing the certificate
# changes the designated requirement and resets permissions again.

set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "usage: Scripts/sign_local.sh <path-to.app>" >&2
    exit 2
fi

SIGN_DIR="${WHISKY_LOCAL_SIGNING_DIR:-$HOME/Library/Application Support/whisky-yaagl/LocalSigning}"
KEYCHAIN="${WHISKY_LOCAL_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/whisky-local-signing.keychain-db}"
KEYCHAIN_PASSWORD="${WHISKY_LOCAL_SIGNING_PASSWORD:-whisky-local}"
P12_PASSWORD="whisky-local-p12"
IDENTITY="Whisky Yaagl Local Code Signing"

mkdir -p "$SIGN_DIR"
chmod 700 "$SIGN_DIR"

ensure_identity_material() {
    if [ -f "$SIGN_DIR/key.pem" ] && [ -f "$SIGN_DIR/cert.pem" ] && [ -f "$SIGN_DIR/identity.p12" ]; then
        return
    fi

    if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
        security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$SIGN_DIR/cert.pem"
        return
    fi

    echo "==> Creating local code-signing certificate"
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$SIGN_DIR/key.pem" \
        -out "$SIGN_DIR/cert.pem" \
        -days 3650 \
        -nodes \
        -subj "/CN=$IDENTITY/O=Whisky Yaagl/C=US" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
    openssl pkcs12 -export -legacy \
        -out "$SIGN_DIR/identity.p12" \
        -inkey "$SIGN_DIR/key.pem" \
        -in "$SIGN_DIR/cert.pem" \
        -name "$IDENTITY" \
        -passout "pass:$P12_PASSWORD" >/dev/null 2>&1
    chmod 600 "$SIGN_DIR/key.pem" "$SIGN_DIR/identity.p12"
}

if [ ! -f "$KEYCHAIN" ] && [ ! -f "${KEYCHAIN%.keychain-db}.keychain" ]; then
    echo "==> Creating local signing keychain"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
ensure_identity_material

if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    if [ ! -f "$SIGN_DIR/identity.p12" ]; then
        echo "error: no local signing identity and no identity.p12 to import." >&2
        exit 1
    fi
    security import "$SIGN_DIR/identity.p12" \
        -k "$KEYCHAIN" \
        -P "$P12_PASSWORD" \
        -T /usr/bin/codesign \
        -T /usr/bin/security
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: \
        -s \
        -k "$KEYCHAIN_PASSWORD" \
        "$KEYCHAIN" >/dev/null
fi

# Keep the dedicated keychain in the user's search list without dropping the
# existing keychains (login, iCloud, etc.).
EXISTING_KEYCHAINS="$(security list-keychains -d user | sed 's/^[[:space:]]*//;s/"//g' | tr '\n' ' ')"
if ! printf '%s\n' "$EXISTING_KEYCHAINS" | grep -Fq "$KEYCHAIN"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $EXISTING_KEYCHAINS
fi

if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> Trusting local code-signing certificate"
    security add-trusted-cert \
        -r trustRoot \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        "$SIGN_DIR/cert.pem"
fi

if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "error: the local signing identity is not trusted." >&2
    security find-identity -p codesigning "$KEYCHAIN" >&2 || true
    exit 1
fi

echo "==> Signing $(basename "$APP") with $IDENTITY"
/usr/bin/codesign \
    --force \
    --deep \
    --sign "$IDENTITY" \
    "$APP"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
REQUIREMENT="$(/usr/bin/codesign -d -r- "$APP" 2>&1 | tail -1)"
echo "==> $REQUIREMENT"

case "$REQUIREMENT" in
    *'certificate root = H"'*)
        ;;
    *)
        echo "error: the signature still has a cdhash-only requirement." >&2
        echo "error: TCC permissions will reset after the next update." >&2
        exit 1
        ;;
esac

/usr/bin/codesign -dvv "$APP" 2>&1 \
    | grep -E '^(Identifier|Authority|TeamIdentifier)=' \
    | head -5 || true

echo "==> Done. Keep $KEYCHAIN and $SIGN_DIR for future updates."

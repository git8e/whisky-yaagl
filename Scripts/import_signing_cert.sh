#!/bin/bash
#
# Imports a base64-encoded Developer ID Application certificate (.p12) into a
# temporary keychain for CI. On success, writes SIGN_IDENTITY,
# DEVELOPMENT_TEAM and SIGNING_KEYCHAIN to $GITHUB_ENV when it is set.
#
# Required environment:
#   APPLE_CERTIFICATE_BASE64    base64 of the exported .p12
#   APPLE_CERTIFICATE_PASSWORD  password used when exporting the .p12
#
# Optional environment:
#   KEYCHAIN_PATH               path for the temporary keychain
#   KEYCHAIN_PASSWORD           password for the temporary keychain

set -euo pipefail

if [ -z "${APPLE_CERTIFICATE_BASE64:-}" ]; then
    echo "error: APPLE_CERTIFICATE_BASE64 is not set." >&2
    exit 1
fi
if [ -z "${APPLE_CERTIFICATE_PASSWORD:-}" ]; then
    echo "error: APPLE_CERTIFICATE_PASSWORD is not set." >&2
    exit 1
fi

KEYCHAIN_PATH="${KEYCHAIN_PATH:-${RUNNER_TEMP:-/tmp}/whisky-signing.keychain-db}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -hex 16)}"
CERT_PATH="$(mktemp)"

cleanup() {
    rm -f "$CERT_PATH"
}
trap cleanup EXIT

printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 -D > "$CERT_PATH"

# Start from a clean keychain so a previous run cannot leak an identity.
security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "$APPLE_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null

# Make the temporary keychain the default and keep the existing search list.
# Keychain paths on macOS runners do not contain spaces.
EXISTING_KEYCHAINS="$(security list-keychains -d user | sed 's/^[[:space:]]*//;s/"//g' | tr '\n' ' ')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS
security default-keychain -d user -s "$KEYCHAIN_PATH"

IDENTITY="$(
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -1
)"
if [ -z "$IDENTITY" ]; then
    echo "error: the imported certificate does not contain a Developer ID Application identity." >&2
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" >&2 || true
    exit 1
fi
TEAM_ID="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')"

echo "==> Imported signing identity: $IDENTITY"
if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "SIGN_IDENTITY=$IDENTITY"
        echo "SIGNING_KEYCHAIN=$KEYCHAIN_PATH"
        if [ -n "$TEAM_ID" ]; then
            echo "DEVELOPMENT_TEAM=$TEAM_ID"
        fi
    } >> "$GITHUB_ENV"
else
    echo "SIGN_IDENTITY=$IDENTITY"
    echo "SIGNING_KEYCHAIN=$KEYCHAIN_PATH"
    [ -z "$TEAM_ID" ] || echo "DEVELOPMENT_TEAM=$TEAM_ID"
fi

#!/bin/bash
#
# Submits an app or DMG to Apple's notary service and staples the ticket.
#
# For an .app bundle this creates a temporary zip for submission, then staples
# the .app itself so the ticket travels with it. For a .dmg (or .pkg) the file
# is submitted and stapled directly.
#
# Credentials are read from the environment, in this order:
#   1. App Store Connect API key:
#        APPSTORE_API_KEY_ID, APPSTORE_API_ISSUER_ID, APPSTORE_API_PRIVATE_KEY
#   2. An existing notarytool keychain profile:
#        NOTARYTOOL_PROFILE
#   3. Apple ID:
#        APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#
# Usage: Scripts/notarize.sh <path-to.app|path-to.dmg|path-to.pkg>

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    echo "usage: Scripts/notarize.sh <path-to.app|path-to.dmg|path-to.pkg>" >&2
    exit 2
fi

WORKDIR=""
TEMP_KEY=""

cleanup() {
    if [ -n "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
    if [ -n "$TEMP_KEY" ]; then
        rm -f "$TEMP_KEY"
    fi
}
trap cleanup EXIT

if [ -d "$TARGET" ] && [[ "$TARGET" == *.app ]]; then
    WORKDIR="$(mktemp -d)"
    SUBMIT="$WORKDIR/$(basename "$TARGET").zip"
    STAPLE="$TARGET"
    echo "==> Creating notarization archive for $(basename "$TARGET")"
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$SUBMIT"
elif [ -f "$TARGET" ] && { [[ "$TARGET" == *.dmg ]] || [[ "$TARGET" == *.pkg ]]; }; then
    SUBMIT="$TARGET"
    STAPLE="$TARGET"
else
    echo "error: notarize.sh expects an .app bundle, .dmg, or .pkg: $TARGET" >&2
    exit 2
fi

NOTARY_ARGS=()
if [ -n "${APPSTORE_API_PRIVATE_KEY:-}" ]; then
    : "${APPSTORE_API_KEY_ID:?APPSTORE_API_KEY_ID is required with APPSTORE_API_PRIVATE_KEY}"
    : "${APPSTORE_API_ISSUER_ID:?APPSTORE_API_ISSUER_ID is required with APPSTORE_API_PRIVATE_KEY}"
    TEMP_KEY="$(mktemp)"
    printf '%s' "$APPSTORE_API_PRIVATE_KEY" > "$TEMP_KEY"
    chmod 600 "$TEMP_KEY"
    NOTARY_ARGS+=(--key "$TEMP_KEY" --key-id "$APPSTORE_API_KEY_ID" --issuer "$APPSTORE_API_ISSUER_ID")
elif [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
    NOTARY_ARGS+=(--keychain-profile "$NOTARYTOOL_PROFILE")
else
    : "${APPLE_ID:?APPLE_ID is required (or configure APPSTORE_API_* / NOTARYTOOL_PROFILE)}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
    NOTARY_ARGS+=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
fi

echo "==> Submitting $(basename "$SUBMIT") to Apple's notary service (this can take a few minutes)"
RESULT="$(xcrun notarytool submit "$SUBMIT" "${NOTARY_ARGS[@]}" --wait --output-format json)"
printf '%s\n' "$RESULT"

json_value() {
    local key="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$RESULT" | jq -r ".${key} // empty"
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$RESULT" | python3 -c 'import json, sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "$key"
    else
        printf '%s' "$RESULT" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
    fi
}

STATUS="$(json_value status)"
SUBMISSION_ID="$(json_value id)"
if [ "$STATUS" != "Accepted" ]; then
    echo "error: notarization finished with status: ${STATUS:-unknown}" >&2
    if [ -n "$SUBMISSION_ID" ]; then
        echo "==> Notary log for $SUBMISSION_ID" >&2
        xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" || true
    fi
    exit 1
fi

echo "==> Stapling notarization ticket to $STAPLE"
xcrun stapler staple "$STAPLE"
xcrun stapler validate "$STAPLE"

if [ -d "$STAPLE" ]; then
    /usr/bin/spctl --assess --type execute --verbose=4 "$STAPLE" || true
else
    /usr/bin/spctl --assess --type open --context context:primary-signature --verbose=4 "$STAPLE" || true
fi

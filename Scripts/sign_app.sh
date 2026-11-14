#!/bin/bash
#
# Signs a built .app bundle.
#
# When a Developer ID Application identity is available (either in
# SIGN_IDENTITY or in the login keychain), the app is signed with it and a
# secure timestamp. Otherwise the app falls back to an ad-hoc signature.
#
# A Developer ID signature keeps the app's designated requirement stable
# across releases (bundle identifier + team identifier), so macOS keeps
# permissions such as Accessibility and Input Monitoring after an update.
# An ad-hoc signature is tied to the code hash, so those permissions are
# reset whenever the app changes; it also cannot pass Gatekeeper.
#
# Usage: Scripts/sign_app.sh [--ad-hoc] [--require-developer-id] <path-to.app>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE_ADHOC=0
REQUIRE_DEVELOPER_ID=0
APP=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ad-hoc)
            FORCE_ADHOC=1
            ;;
        --require-developer-id)
            REQUIRE_DEVELOPER_ID=1
            ;;
        -h|--help)
            sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "error: unknown option: $1" >&2
            exit 2
            ;;
        *)
            if [ -n "$APP" ]; then
                echo "error: only one .app path may be given" >&2
                exit 2
            fi
            APP="$1"
            ;;
    esac
    shift
done

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "usage: Scripts/sign_app.sh [--ad-hoc] [--require-developer-id] <path-to.app>" >&2
    exit 2
fi

# Prefer an explicit identity (for example from CI), then the first Developer
# ID Application identity in the keychain. Ad-hoc is the final fallback.
IDENTITY="${SIGN_IDENTITY:-}"
if [ "$FORCE_ADHOC" = "1" ]; then
    IDENTITY="-"
elif [ -z "$IDENTITY" ]; then
    IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
            | head -1
    )"
fi

if [ -z "$IDENTITY" ]; then
    if [ "$REQUIRE_DEVELOPER_ID" = "1" ]; then
        echo "error: no Developer ID Application identity found." >&2
        echo "Install a Developer ID certificate in the keychain or set SIGN_IDENTITY." >&2
        exit 1
    fi
    IDENTITY="-"
fi

# Preserve entitlements and hardening flags when replacing an existing
# signature. This matters when an app was built with Xcode signing enabled and
# then needs to be re-signed with a different identity.
PRESERVE=()
if /usr/bin/codesign -d "$APP" >/dev/null 2>&1; then
    PRESERVE=(--preserve-metadata=entitlements,flags,runtime)
fi

if [ "$IDENTITY" = "-" ]; then
    echo "==> Ad-hoc signing $(basename "$APP")"
    if [ "${#PRESERVE[@]}" -gt 0 ]; then
        /usr/bin/codesign --force --deep "${PRESERVE[@]}" --sign - "$APP"
    else
        /usr/bin/codesign --force --deep --sign - "$APP"
    fi
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

    echo "warning: this build uses an ad-hoc signature." >&2
    echo "warning: macOS may block the first launch and may ask for Accessibility" >&2
    echo "warning: or other permissions again after every update." >&2
    exit 0
fi

# If the app is already signed with the requested identity, leave the
# signature alone. Re-signing an Xcode-signed app with --deep can lose the
# per-target entitlements that Xcode applied.
CURRENT_SIGNATURE="$(/usr/bin/codesign -dvv "$APP" 2>&1 || true)"
CURRENT_AUTHORITY="$(printf '%s\n' "$CURRENT_SIGNATURE" | sed -n 's/^Authority=//p' | head -1)"
CURRENT_TEAM="$(printf '%s\n' "$CURRENT_SIGNATURE" | sed -n 's/^TeamIdentifier=//p' | head -1)"
TARGET_TEAM="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')"

if [ "$CURRENT_AUTHORITY" = "$IDENTITY" ] \
    && { [ -z "$TARGET_TEAM" ] || [ "$CURRENT_TEAM" = "$TARGET_TEAM" ]; } \
    && /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    echo "==> Already signed with $IDENTITY"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
else
    echo "==> Signing $(basename "$APP") with $IDENTITY"
    if [ "${#PRESERVE[@]}" -gt 0 ]; then
        /usr/bin/codesign \
            --force \
            --deep \
            "${PRESERVE[@]}" \
            --options runtime \
            --timestamp \
            --sign "$IDENTITY" \
            "$APP"
    else
        /usr/bin/codesign \
            --force \
            --deep \
            --options runtime \
            --timestamp \
            --sign "$IDENTITY" \
            "$APP"
    fi
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
fi

/usr/bin/codesign -dvv "$APP" 2>&1 \
    | grep -E '^(Identifier|Authority|TeamIdentifier)=' \
    | head -5 || true

if /usr/bin/spctl --assess --type execute --verbose=4 "$APP" 2>&1 | grep -q 'accepted'; then
    echo "==> Gatekeeper assessment passed"
else
    echo "note: Gatekeeper did not accept this build yet (it may still need to be notarized)." >&2
fi

#!/bin/bash
#
# Builds the Release app with xcodebuild and optionally copies it to a path.
#
# If a Developer ID Application identity is available, the project is built
# with that identity and a secure timestamp so macOS keeps TCC permissions
# across updates. Otherwise the project is built unsigned and the output is
# ad-hoc signed, which is useful for local testing but cannot pass Gatekeeper.
#
# Usage:
#   Scripts/build_app.sh --build-only
#   Scripts/build_app.sh --output build/whisky-yaagl.app
#
# Options:
#   --configuration <name>   Build configuration (default: Release)
#   --derived-data <path>    DerivedData path (default: build/DerivedData)
#   --output <path>          Copy the built app here and sign/verify it
#   --build-only             Do not copy or sign; only run xcodebuild
#   --ad-hoc                 Force an unsigned build with ad-hoc signing
#   --require-developer-id   Fail instead of falling back to ad-hoc signing

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="Release"
DERIVED_DATA="$ROOT/build/DerivedData"
OUTPUT=""
BUILD_ONLY=0
FORCE_ADHOC=0
REQUIRE_DEVELOPER_ID=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --configuration)
            CONFIGURATION="${2:?missing value for --configuration}"
            shift
            ;;
        --derived-data)
            DERIVED_DATA="${2:?missing value for --derived-data}"
            shift
            ;;
        --output)
            OUTPUT="${2:?missing value for --output}"
            shift
            ;;
        --build-only)
            BUILD_ONLY=1
            ;;
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
        *)
            echo "error: unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$BUILD_ONLY" = "0" ] && [ -z "$OUTPUT" ]; then
    echo "error: --output is required unless --build-only is given" >&2
    exit 2
fi

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

TEAM_ID="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM_ID" ] && [ "$IDENTITY" != "-" ]; then
    TEAM_ID="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p')"
fi

COMMON_ARGS=(
    -project "$ROOT/Whisky.xcodeproj"
    -scheme "Whisky"
    -configuration "$CONFIGURATION"
    -destination "platform=macOS"
    -derivedDataPath "$DERIVED_DATA"
)

if [ "$IDENTITY" = "-" ]; then
    echo "==> No Developer ID identity found; building unsigned (ad-hoc fallback)"
    SKIP_SWIFTLINT="${SKIP_SWIFTLINT:-1}" xcodebuild \
        "${COMMON_ARGS[@]}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        build
else
    echo "==> Building with signing identity: $IDENTITY"
    SIGN_ARGS=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGNING_REQUIRED=YES
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="$IDENTITY"
        "CODE_SIGN_IDENTITY[sdk=macosx*]=$IDENTITY"
        ENABLE_HARDENED_RUNTIME=YES
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
    if [ -n "$TEAM_ID" ]; then
        SIGN_ARGS+=(
            "DEVELOPMENT_TEAM=$TEAM_ID"
            "DEVELOPMENT_TEAM[sdk=macosx*]=$TEAM_ID"
        )
    fi
    SKIP_SWIFTLINT="${SKIP_SWIFTLINT:-1}" xcodebuild \
        "${COMMON_ARGS[@]}" \
        "${SIGN_ARGS[@]}" \
        build
fi

PRODUCT="$DERIVED_DATA/Build/Products/$CONFIGURATION/whisky-yaagl.app"
if [ ! -d "$PRODUCT" ]; then
    echo "error: expected product not found: $PRODUCT" >&2
    exit 1
fi

if [ "$BUILD_ONLY" = "1" ]; then
    echo "==> Built $PRODUCT"
    exit 0
fi

rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
ditto "$PRODUCT" "$OUTPUT"

if [ "$IDENTITY" = "-" ]; then
    "$ROOT/Scripts/sign_app.sh" --ad-hoc "$OUTPUT"
else
    "$ROOT/Scripts/sign_app.sh" "$OUTPUT"
fi

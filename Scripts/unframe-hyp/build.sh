#!/bin/sh
# Rebuilds the HoYoPlay frameless-window helper that ships as a WhiskyKit
# resource. Requires a MinGW-w64 cross compiler:
#
#   brew install mingw-w64
#
set -eu
cd "$(dirname "$0")"

CFLAGS="-Os -s -municode"
OUTPUT="../../WhiskyKit/Sources/WhiskyKit/Resources/unframe-hyp.exe"

x86_64-w64-mingw32-gcc $CFLAGS -o "$OUTPUT" unframe-hyp.c
echo "built $OUTPUT"

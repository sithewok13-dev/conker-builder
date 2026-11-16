#!/bin/sh
# Prints the name of the ready-made parts that fit these sources and this Mac's tools:
# conker-parts-<16 hex>.tar.xz. parts.yml makes it; build.yml uses it when the name matches.
set -e
cd "$(dirname "$0")/.."
{
    xcodebuild -version 2>/dev/null || echo "no xcode"
    cmake --version | head -1
    find port/CMakeLists.txt port/sources.txt port/patches port/ios -name '*.txt' -o -name '*.patch' -o -name '*.cmake' \
        | LC_ALL=C sort | while read -r f; do echo "$f"; cat "$f"; done
    cat tools/configure.sh tools/configure-seed.py
} | shasum -a 256 | cut -c1-16 | sed 's/^/conker-parts-/; s/$/.tar.xz/'

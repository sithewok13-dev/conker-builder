#!/bin/sh
# Fetches the port's pinned sources (port/sources.txt) into port/third_party.
#   tools/fetch-sources.sh recompiler   CBFD-Recompiled and its N64Recomp (to turn the ROM into C)
#   tools/fetch-sources.sh app          everything the iOS app builds from
# Run from the repository's top folder. Already fetched sources at the right commit are kept.
set -e
what=${1:-app}
cd "$(dirname "$0")/../port"

fetch() { # path url commit
    if [ "$(git -C "$1" rev-parse HEAD 2>/dev/null)" = "$3" ]; then echo "$1: already at $3"; return; fi
    rm -rf "$1"; mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" remote add origin "$2"
    git -C "$1" fetch -q --depth 1 origin "$3"
    git -C "$1" -c advice.detachedHead=false checkout -q FETCH_HEAD
    echo "$1: $3"
}

grep -v '^#' sources.txt | while read -r path url commit; do
    [ -n "$path" ] || continue
    case "$what:$path" in
        recompiler:third_party/CBFD-Recompiled|app:*) fetch "$path" "$url" "$commit" ;;
    esac
done

# CBFD-Recompiled's own pinned tools (not the decompilation's).
if [ "$what" = recompiler ]; then tools="tools/N64Recomp"
else tools="tools/N64ModernRuntime tools/rt64 tools/RecompFrontend"; fi
cd third_party/CBFD-Recompiled
# shallow first; some servers refuse a shallow fetch of an old commit, so then in full
# shellcheck disable=SC2086
git submodule update --init --recursive --depth 1 --jobs 8 $tools ||
    git submodule update --init --recursive --jobs 8 $tools

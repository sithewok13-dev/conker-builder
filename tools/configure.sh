#!/bin/sh
# Configures the iOS game build (Xcode project in build/), the same way for build.yml and parts.yml.
#   tools/configure.sh <RecompiledFuncs folder> <bundle id> [seed.cmake]
set -e
cd "$(dirname "$0")/.."
gen=$1 bundle=$2 seed=$3
set --
[ -n "$seed" ] && [ -f "$seed" ] && set -- -C "$seed"
cmake "$@" -S port -B build -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    "-DCONKER_BUNDLE_ID=$bundle" \
    "-DCONKER_GENERATED_DIR=$gen"

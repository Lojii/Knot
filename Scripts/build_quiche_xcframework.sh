#!/bin/bash
#
# build_quiche_xcframework.sh
# Builds Cloudflare's quiche (QUIC + HTTP/3) as an XCFramework.
#
# Usage: ./build_quiche_xcframework.sh [ios|macos|all]
# Source cache: ~/.cache/knot-build/quiche (avoids repeated git clone)
#
set -euo pipefail

PLATFORM="${1:-all}"

export PATH="$HOME/.cargo/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${KNOT_BUILD_CACHE:-$HOME/.cache/knot-build}"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"

echo "=== Building quiche XCFramework (platform: $PLATFORM) ==="

# Step 1: Get source (cached)
QUICHE_SRC="$CACHE_DIR/quiche"
if [ -d "$QUICHE_SRC/.git" ]; then
    echo "--- Using cached quiche source: $QUICHE_SRC ---"
    cd "$QUICHE_SRC"
    git fetch --depth 1 origin 2>&1 | tail -3 || true
    git reset --hard origin/HEAD 2>&1 | tail -1 || true
    git submodule update --init --recursive --depth 1 2>&1 | tail -3 || true
else
    echo "--- Clone quiche (first time, will be cached) ---"
    mkdir -p "$CACHE_DIR"
    rm -rf "$QUICHE_SRC"
    git clone --depth 1 --recursive https://github.com/cloudflare/quiche.git "$QUICHE_SRC" 2>&1 | tail -5
    cd "$QUICHE_SRC"
fi

# No cargo clean needed — each platform uses a different --target, so builds don't conflict.

# Step 2: Set up iOS SDK paths
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    # Step 3: Build for iOS device
    echo "--- Build for iOS device (aarch64-apple-ios) ---"
    export CFLAGS="-isysroot $IOS_SDK"
    export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER=$(xcrun --sdk iphoneos --find clang)
    export CC_aarch64_apple_ios="$(xcrun --sdk iphoneos --find clang)"
    export AR_aarch64_apple_ios="$(xcrun --sdk iphoneos --find ar)"

    cargo build \
        --package quiche \
        --release \
        --features ffi \
        --target aarch64-apple-ios \
        2>&1 | tail -5

    # Step 4: Build for iOS Simulator
    echo "--- Build for iOS Simulator (aarch64-apple-ios-sim) ---"
    export CFLAGS="-isysroot $SIM_SDK"
    export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER=$(xcrun --sdk iphonesimulator --find clang)
    export CC_aarch64_apple_ios_sim="$(xcrun --sdk iphonesimulator --find clang)"
    export AR_aarch64_apple_ios_sim="$(xcrun --sdk iphonesimulator --find ar)"

    cargo build \
        --package quiche \
        --release \
        --features ffi \
        --target aarch64-apple-ios-sim \
        2>&1 | tail -5
fi

if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    echo "--- Build for macOS (aarch64-apple-darwin) ---"
    unset CFLAGS CARGO_TARGET_AARCH64_APPLE_IOS_LINKER CC_aarch64_apple_ios AR_aarch64_apple_ios 2>/dev/null || true
    unset CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER CC_aarch64_apple_ios_sim AR_aarch64_apple_ios_sim 2>/dev/null || true
    export MACOSX_DEPLOYMENT_TARGET=14.0
    cargo build \
        --package quiche \
        --release \
        --features ffi \
        --target aarch64-apple-darwin \
        2>&1 | tail -5

    echo "--- Build for macOS (x86_64-apple-darwin) ---"
    cargo build \
        --package quiche \
        --release \
        --features ffi \
        --target x86_64-apple-darwin \
        2>&1 | tail -5

    echo "--- Create macOS Universal binary ---"
    mkdir -p target/universal-macos/release
    lipo -create \
        target/aarch64-apple-darwin/release/libquiche.a \
        target/x86_64-apple-darwin/release/libquiche.a \
        -output target/universal-macos/release/libquiche.a
fi

# Step 5: Prepare headers
echo "--- Prepare headers ---"
HEADER_DIR="$(mktemp -d)/headers/CQuiche"
mkdir -p "$HEADER_DIR"
cp quiche/include/quiche.h "$HEADER_DIR/"

cat > "$HEADER_DIR/module.modulemap" << 'MAPEOF'
module CQuiche {
    header "quiche.h"
    link "quiche"
    export *
}
MAPEOF
HEADER_ROOT="$(dirname "$HEADER_DIR")"

# Step 6: Create XCFramework
echo "--- Create XCFramework ---"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/CQuiche.xcframework"
rm -rf "$OUTPUT_DIR/Quiche.xcframework"  # cleanup old name

XCFW_ARGS=()
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "target/aarch64-apple-ios/release/libquiche.a" -headers "$HEADER_ROOT")
    XCFW_ARGS+=(-library "target/aarch64-apple-ios-sim/release/libquiche.a" -headers "$HEADER_ROOT")
fi
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "target/universal-macos/release/libquiche.a" -headers "$HEADER_ROOT")
fi

xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/CQuiche.xcframework"

echo "=== Done ==="
find "$OUTPUT_DIR/CQuiche.xcframework" -name "*.a" -exec ls -lh {} \;

#!/bin/bash
#
# build_quiche_xcframework.sh
# Builds Cloudflare's quiche (QUIC + HTTP/3) as an iOS XCFramework.
#
set -euo pipefail

PLATFORM="${1:-all}"

export PATH="$HOME/.cargo/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$(mktemp -d)"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"

echo "=== Building quiche XCFramework ==="

# Step 1: Clone
echo "--- Clone quiche ---"
git clone --depth 1 --recursive https://github.com/cloudflare/quiche.git "$WORK_DIR/quiche" 2>&1 | tail -3
cd "$WORK_DIR/quiche"

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
    unset CFLAGS CARGO_TARGET_AARCH64_APPLE_IOS_LINKER CC_aarch64_apple_ios AR_aarch64_apple_ios
    unset CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER CC_aarch64_apple_ios_sim AR_aarch64_apple_ios_sim
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
HEADER_DIR="$WORK_DIR/headers"
mkdir -p "$HEADER_DIR"
cp quiche/include/quiche.h "$HEADER_DIR/"

cat > "$HEADER_DIR/module.modulemap" << 'MAPEOF'
module CQuiche {
    header "quiche.h"
    link "quiche"
    export *
}
MAPEOF

# Step 6: Create XCFramework
echo "--- Create XCFramework ---"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/CQuiche.xcframework"
rm -rf "$OUTPUT_DIR/Quiche.xcframework"  # cleanup old name

XCFW_ARGS=()
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "target/aarch64-apple-ios/release/libquiche.a" -headers "$HEADER_DIR")
    XCFW_ARGS+=(-library "target/aarch64-apple-ios-sim/release/libquiche.a" -headers "$HEADER_DIR")
fi
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "target/universal-macos/release/libquiche.a" -headers "$HEADER_DIR")
fi

xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/CQuiche.xcframework"

echo "=== Done ==="
find "$OUTPUT_DIR/CQuiche.xcframework" -name "*.a" -exec ls -lh {} \;

rm -rf "$WORK_DIR"

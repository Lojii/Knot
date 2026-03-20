#!/bin/bash
#
# build_lsquic_xcframework.sh
# Builds LiteSpeed's lsquic as an XCFramework.
#
# lsquic is pure C, compiled with CMake.
# Depends on BoringSSL (bundled).
#
# Usage: ./build_lsquic_xcframework.sh [ios|macos|all]
# Source cache: ~/.cache/knot-build/lsquic (avoids repeated git clone)
#
set -euo pipefail

PLATFORM="${1:-all}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${KNOT_BUILD_CACHE:-$HOME/.cache/knot-build}"
BUILD_DIR="$(mktemp -d)"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"

echo "=== Building lsquic XCFramework (platform: $PLATFORM) ==="

# Step 1: Get lsquic source (cached)
LSQUIC_SRC="$CACHE_DIR/lsquic"
if [ -d "$LSQUIC_SRC/.git" ]; then
    echo "--- Using cached lsquic source: $LSQUIC_SRC ---"
    cd "$LSQUIC_SRC"
    git fetch --depth 1 origin 2>&1 | tail -3 || true
    git reset --hard origin/HEAD 2>&1 | tail -1 || true
    git submodule update --init --recursive --depth 1 2>&1 | tail -3 || true
else
    echo "--- Clone lsquic (first time, will be cached) ---"
    mkdir -p "$CACHE_DIR"
    rm -rf "$LSQUIC_SRC"
    git clone --depth 1 --recursive https://github.com/litespeedtech/lsquic.git "$LSQUIC_SRC" 2>&1 | tail -5
    cd "$LSQUIC_SRC"
fi

# Step 1b: Get BoringSSL source (cached, not a submodule of lsquic)
BSSL_SRC="$CACHE_DIR/boringssl"
if [ -d "$BSSL_SRC/.git" ]; then
    echo "--- Using cached BoringSSL source: $BSSL_SRC ---"
    cd "$BSSL_SRC"
    git fetch --depth 1 origin 2>&1 | tail -3 || true
    git reset --hard origin/HEAD 2>&1 | tail -1 || true
else
    echo "--- Clone BoringSSL (first time, will be cached) ---"
    mkdir -p "$CACHE_DIR"
    rm -rf "$BSSL_SRC"
    git clone --depth 1 https://boringssl.googlesource.com/boringssl "$BSSL_SRC" 2>&1 | tail -5
fi

# Symlink BoringSSL into lsquic source tree (lsquic expects third_party/boringssl)
rm -rf "$LSQUIC_SRC/third_party/boringssl"
mkdir -p "$LSQUIC_SRC/third_party"
ln -sf "$BSSL_SRC" "$LSQUIC_SRC/third_party/boringssl"

cd "$LSQUIC_SRC"

if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
    SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

    # Step 2: Build BoringSSL for iOS
    echo "--- Build BoringSSL for iOS ---"
    rm -rf "$BUILD_DIR/boringssl-ios"
    mkdir -p "$BUILD_DIR/boringssl-ios" && cd "$BUILD_DIR/boringssl-ios"
    cmake "$LSQUIC_SRC/third_party/boringssl" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCMAKE_MACOSX_BUNDLE=OFF \
        2>&1 | tail -5
    cmake --build . --config Release --target ssl crypto -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    BSSL_IOS="$BUILD_DIR/boringssl-ios"

    # Step 3: Build lsquic for iOS device
    echo "--- Build lsquic for iOS device ---"
    rm -rf "$BUILD_DIR/lsquic-ios"
    mkdir -p "$BUILD_DIR/lsquic-ios" && cd "$BUILD_DIR/lsquic-ios"
    cmake "$LSQUIC_SRC" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DBORINGSSL_DIR="$BSSL_IOS" \
        -DLSQUIC_BIN=OFF \
        -DLSQUIC_TESTS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release --target lsquic -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    IOS_LIB="$BUILD_DIR/lsquic-ios/src/liblsquic/liblsquic.a"

    # Step 4: Build BoringSSL for Simulator
    echo "--- Build BoringSSL for Simulator ---"
    rm -rf "$BUILD_DIR/boringssl-sim"
    mkdir -p "$BUILD_DIR/boringssl-sim" && cd "$BUILD_DIR/boringssl-sim"
    cmake "$LSQUIC_SRC/third_party/boringssl" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$SIM_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_C_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DCMAKE_ASM_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCMAKE_MACOSX_BUNDLE=OFF \
        2>&1 | tail -5
    cmake --build . --config Release --target ssl crypto -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    BSSL_SIM_BUILD="$BUILD_DIR/boringssl-sim"

    # Step 5: Build lsquic for Simulator
    echo "--- Build lsquic for Simulator ---"
    rm -rf "$BUILD_DIR/lsquic-sim"
    mkdir -p "$BUILD_DIR/lsquic-sim" && cd "$BUILD_DIR/lsquic-sim"
    cmake "$LSQUIC_SRC" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$SIM_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_C_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DCMAKE_ASM_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DBORINGSSL_DIR="$BSSL_SIM_BUILD" \
        -DLSQUIC_BIN=OFF \
        -DLSQUIC_TESTS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release --target lsquic -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    SIM_LIB="$BUILD_DIR/lsquic-sim/src/liblsquic/liblsquic.a"

    # Step 6: Merge BoringSSL into lsquic libs
    echo "--- Merge iOS libraries ---"
    mkdir -p "$BUILD_DIR/merged"
    libtool -static -o "$BUILD_DIR/merged/liblsquic-ios.a" \
        "$IOS_LIB" \
        "$BSSL_IOS/libssl.a" \
        "$BSSL_IOS/libcrypto.a"

    libtool -static -o "$BUILD_DIR/merged/liblsquic-sim.a" \
        "$SIM_LIB" \
        "$BSSL_SIM_BUILD/libssl.a" \
        "$BSSL_SIM_BUILD/libcrypto.a"
fi

if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    # Build BoringSSL for macOS with symbol prefix to avoid collision with swift-nio-ssl
    echo "--- Build BoringSSL for macOS (prefixed) ---"
    rm -rf "$BUILD_DIR/boringssl-macos"
    mkdir -p "$BUILD_DIR/boringssl-macos" && cd "$BUILD_DIR/boringssl-macos"
    cmake "$LSQUIC_SRC/third_party/boringssl" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBORINGSSL_PREFIX=lsquic_ \
        -DCMAKE_C_FLAGS="-fvisibility=hidden" \
        -DCMAKE_CXX_FLAGS="-fvisibility=hidden -fvisibility-inlines-hidden" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCMAKE_MACOSX_BUNDLE=OFF \
        2>&1 | tail -10
    cmake --build . --config Release --target ssl crypto -j$(sysctl -n hw.ncpu) 2>&1 | tail -5
    BSSL_MACOS="$BUILD_DIR/boringssl-macos"

    echo "--- Build lsquic for macOS (Universal) ---"
    rm -rf "$BUILD_DIR/lsquic-macos"
    mkdir -p "$BUILD_DIR/lsquic-macos" && cd "$BUILD_DIR/lsquic-macos"
    cmake "$LSQUIC_SRC" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBORINGSSL_DIR="$BSSL_MACOS" \
        -DBORINGSSL_INCLUDE="$LSQUIC_SRC/third_party/boringssl/include" \
        -DCMAKE_C_FLAGS="-DBORINGSSL_PREFIX=lsquic_" \
        -DLSQUIC_BIN=OFF \
        -DLSQUIC_TESTS=OFF \
        2>&1 | tail -10
    cmake --build . --config Release --target lsquic -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    MACOS_LIB="$BUILD_DIR/lsquic-macos/src/liblsquic/liblsquic.a"

    echo "--- Merge macOS libraries ---"
    mkdir -p "$BUILD_DIR/merged"
    libtool -static -o "$BUILD_DIR/merged/liblsquic-merged.a" \
        "$MACOS_LIB" \
        "$BSSL_MACOS/libssl.a" \
        "$BSSL_MACOS/libcrypto.a"

    # Hide BoringSSL C++ symbols to avoid conflicts with swift-nio-ssl's CNIOBoringSSL.
    # Only hide bare (non-namespaced) constructors/destructors; keep bssl::lsquic_:: symbols.
    echo "--- Hide BoringSSL C++ symbols ---"
    nm "$BUILD_DIR/merged/liblsquic-merged.a" | grep " T " | grep -E "__ZN(6ssl_st|10ssl_ctx_st|14ssl_session_st)" | grep -v "lsquic_" | awk '{print $3}' | sort -u > "$BUILD_DIR/merged/hide_symbols.txt"
    if [ -s "$BUILD_DIR/merged/hide_symbols.txt" ]; then
        nmedit -R "$BUILD_DIR/merged/hide_symbols.txt" "$BUILD_DIR/merged/liblsquic-merged.a" -o "$BUILD_DIR/merged/liblsquic.a" 2>/dev/null
    else
        cp "$BUILD_DIR/merged/liblsquic-merged.a" "$BUILD_DIR/merged/liblsquic.a"
    fi
fi

# Step 7: Prepare headers
echo "--- Prepare headers ---"
HEADER_DIR="$BUILD_DIR/headers/CLsquic"
mkdir -p "$HEADER_DIR"
cp "$LSQUIC_SRC/include/lsquic.h" "$HEADER_DIR/"
cp "$LSQUIC_SRC/include/lsquic_types.h" "$HEADER_DIR/"
cp "$LSQUIC_SRC/include/lsxpack_header.h" "$HEADER_DIR/"

cat > "$HEADER_DIR/module.modulemap" << 'MAPEOF'
module CLsquic {
    header "lsquic.h"
    header "lsquic_types.h"
    header "lsxpack_header.h"
    link "lsquic"
    export *
}
MAPEOF
HEADER_ROOT="$BUILD_DIR/headers"

# Step 8: Create XCFramework
echo "--- Create XCFramework ---"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/CLsquic.xcframework"

XCFW_ARGS=()
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "$BUILD_DIR/merged/liblsquic-ios.a" -headers "$HEADER_ROOT")
    XCFW_ARGS+=(-library "$BUILD_DIR/merged/liblsquic-sim.a" -headers "$HEADER_ROOT")
fi
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "$BUILD_DIR/merged/liblsquic.a" -headers "$HEADER_ROOT")
fi

xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/CLsquic.xcframework"

echo "=== Done ==="
find "$OUTPUT_DIR/CLsquic.xcframework" -name "*.a" -exec ls -lh {} \;

rm -rf "$BUILD_DIR"

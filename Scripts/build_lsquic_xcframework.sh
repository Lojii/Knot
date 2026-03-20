#!/bin/bash
#
# build_lsquic_xcframework.sh
# Builds LiteSpeed's lsquic as an iOS XCFramework.
#
# lsquic is pure C, compiled with CMake.
# Depends on BoringSSL (bundled).
#
set -euo pipefail

PLATFORM="${1:-all}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$(mktemp -d)"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"

echo "=== Building lsquic XCFramework ==="

# Step 1: Clone lsquic with submodules
echo "--- Clone lsquic ---"
git clone --depth 1 --recursive https://github.com/litespeedtech/lsquic.git "$WORK_DIR/lsquic" 2>&1 | tail -3
cd "$WORK_DIR/lsquic"

# Step 1b: Clone BoringSSL (not a submodule of lsquic)
echo "--- Clone BoringSSL ---"
git clone --depth 1 https://boringssl.googlesource.com/boringssl "$WORK_DIR/lsquic/third_party/boringssl" 2>&1 | tail -3

if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
    SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

    # Step 2: Build BoringSSL for iOS
    echo "--- Build BoringSSL for iOS ---"
    mkdir -p boringssl-build-ios && cd boringssl-build-ios
    cmake ../third_party/boringssl \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$IOS_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DBUILD_SHARED_LIBS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    BSSL_IOS="$WORK_DIR/lsquic/boringssl-build-ios"
    cd ..

    # Step 3: Build lsquic for iOS device
    echo "--- Build lsquic for iOS device ---"
    mkdir -p build-ios && cd build-ios
    cmake .. \
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
    IOS_LIB="$WORK_DIR/lsquic/build-ios/src/liblsquic/liblsquic.a"
    cd ..

    # Step 4: Build BoringSSL for Simulator
    echo "--- Build BoringSSL for Simulator ---"
    mkdir -p boringssl-build-sim && cd boringssl-build-sim
    cmake ../third_party/boringssl \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$SIM_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_C_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DCMAKE_ASM_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DBUILD_SHARED_LIBS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    BSSL_SIM="$WORK_DIR/lsquic/boringssl-build-sim"
    cd ..

    # Step 5: Build lsquic for Simulator
    echo "--- Build lsquic for Simulator ---"
    mkdir -p build-sim && cd build-sim
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$SIM_SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_C_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DCMAKE_ASM_FLAGS="-target arm64-apple-ios15.0-simulator" \
        -DBORINGSSL_DIR="$BSSL_SIM" \
        -DLSQUIC_BIN=OFF \
        -DLSQUIC_TESTS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release --target lsquic -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    SIM_LIB="$WORK_DIR/lsquic/build-sim/src/liblsquic/liblsquic.a"
    cd ..

    # Step 6: Merge BoringSSL into lsquic libs
    echo "--- Merge libraries ---"
    mkdir -p "$WORK_DIR/merged"
    libtool -static -o "$WORK_DIR/merged/liblsquic-ios.a" \
        "$IOS_LIB" \
        "$BSSL_IOS/ssl/libssl.a" \
        "$BSSL_IOS/crypto/libcrypto.a"

    libtool -static -o "$WORK_DIR/merged/liblsquic-sim.a" \
        "$SIM_LIB" \
        "$BSSL_SIM/ssl/libssl.a" \
        "$BSSL_SIM/crypto/libcrypto.a"
fi

if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    echo "--- Build BoringSSL for macOS (prefixed) ---"
    mkdir -p boringssl-build-macos && cd boringssl-build-macos
    cmake ../third_party/boringssl \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBORINGSSL_PREFIX=lsquic_ \
        -DBUILD_SHARED_LIBS=OFF \
        2>&1 | tail -10
    cmake --build . --config Release --target ssl crypto -j$(sysctl -n hw.ncpu) 2>&1 | tail -5
    BSSL_MACOS="$WORK_DIR/lsquic/boringssl-build-macos"
    cd ..
fi

if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    echo "--- Build lsquic for macOS (Universal) ---"
    mkdir -p build-macos && cd build-macos
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DBORINGSSL_DIR="$BSSL_MACOS" \
        -DLSQUIC_BIN=OFF \
        -DLSQUIC_TESTS=OFF \
        2>&1 | tail -3
    cmake --build . --config Release --target lsquic -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
    MACOS_LIB="$WORK_DIR/lsquic/build-macos/src/liblsquic/liblsquic.a"
    cd ..

    echo "--- Merge macOS libraries ---"
    mkdir -p "$WORK_DIR/merged"
    libtool -static -o "$WORK_DIR/merged/liblsquic-macos.a" \
        "$MACOS_LIB" \
        "$BSSL_MACOS/ssl/libssl.a" \
        "$BSSL_MACOS/crypto/libcrypto.a"
fi

# Step 7: Prepare headers
echo "--- Prepare headers ---"
HEADER_DIR="$WORK_DIR/headers"
mkdir -p "$HEADER_DIR"
cp include/lsquic.h "$HEADER_DIR/"
cp include/lsquic_types.h "$HEADER_DIR/"
cp include/lsxpack_header.h "$HEADER_DIR/"

cat > "$HEADER_DIR/module.modulemap" << 'MAPEOF'
module CLsquic {
    header "lsquic.h"
    header "lsquic_types.h"
    header "lsxpack_header.h"
    link "lsquic"
    export *
}
MAPEOF

# Step 8: Create XCFramework
echo "--- Create XCFramework ---"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/CLsquic.xcframework"

XCFW_ARGS=()
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "$WORK_DIR/merged/liblsquic-ios.a" -headers "$HEADER_DIR")
    XCFW_ARGS+=(-library "$WORK_DIR/merged/liblsquic-sim.a" -headers "$HEADER_DIR")
fi
if [[ "$PLATFORM" == "macos" || "$PLATFORM" == "all" ]]; then
    XCFW_ARGS+=(-library "$WORK_DIR/merged/liblsquic-macos.a" -headers "$HEADER_DIR")
fi

xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/CLsquic.xcframework"

echo "=== Done ==="
find "$OUTPUT_DIR/CLsquic.xcframework" -name "*.a" -exec ls -lh {} \;

rm -rf "$WORK_DIR"

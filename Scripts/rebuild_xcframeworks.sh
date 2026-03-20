#!/bin/bash
#
# rebuild_xcframeworks.sh
# Rebuilds all QUIC xcframeworks for all platforms.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM="${1:-all}"  # ios, macos, all

echo "=== Rebuilding QUIC XCFrameworks (platform: $PLATFORM) ==="

echo ""
echo ">>> Building quiche..."
"$SCRIPT_DIR/build_quiche_xcframework.sh" "$PLATFORM"

echo ""
echo ">>> Building lsquic..."
"$SCRIPT_DIR/build_lsquic_xcframework.sh" "$PLATFORM"

echo ""
echo "=== All XCFrameworks rebuilt ==="
ls -lh "$SCRIPT_DIR/../Frameworks/"*.xcframework/*/lib*.a 2>/dev/null || true

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$PROJECT_DIR/LocalPackages/TunnelServices"
REPORT_DIR="${TEST_REPORT_DIR:-$PROJECT_DIR/build/test-reports}"

mkdir -p "$REPORT_DIR"

# Parse args
RUN_ALL=false
FILTER=""
STRESS_ONLY=false
NO_OPEN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)         RUN_ALL=true; shift ;;
        --filter)      FILTER="$2"; shift 2 ;;
        --stress-only) STRESS_ONLY=true; shift ;;
        --no-open)     NO_OPEN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --all          Include heavy stress tests (RUN_STRESS_HEAVY=1)"
            echo "  --filter NAME  Only tests matching NAME"
            echo "  --stress-only  Only stress tests"
            echo "  --no-open      Don't open HTML report"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# Build test filter
if [[ -n "$FILTER" ]]; then
    SWIFT_FILTER="--filter $FILTER"
elif [[ "$STRESS_ONLY" == "true" ]]; then
    SWIFT_FILTER="--filter Stress"
else
    SWIFT_FILTER="--filter Integration|EdgeCase|Stress"
fi

[[ "$RUN_ALL" == "true" ]] && export RUN_STRESS_HEAVY=1

echo "=== TunnelServices Integration Tests ==="
echo "Report: $REPORT_DIR"
echo ""

# Run with JUnit XML + capture stdout
set +e
swift test \
    --package-path "$PACKAGE_DIR" \
    --xunit-output "$REPORT_DIR/results.xml" \
    $SWIFT_FILTER \
    2>&1 | tee "$REPORT_DIR/test-output.log"
TEST_EXIT=$?
set -e

# Generate HTML report
if [[ -f "$REPORT_DIR/results.xml" ]]; then
    swift "$SCRIPT_DIR/generate-test-report.swift" \
        "$REPORT_DIR/results.xml" \
        "$REPORT_DIR/test-output.log" \
        "$REPORT_DIR/integration-test-report.html"

    [[ "$NO_OPEN" != "true" ]] && open "$REPORT_DIR/integration-test-report.html" 2>/dev/null || true
fi

echo ""
echo "HTML Report: $REPORT_DIR/integration-test-report.html"
exit $TEST_EXIT

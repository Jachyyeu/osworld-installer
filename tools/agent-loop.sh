#!/bin/bash
# Usage: ./agent-loop.sh [--confirm] [--max-iterations N]
# Autonomous test-detect-fix loop for the AltOS installer.

set -uo pipefail
# -e is intentionally omitted because test failures are expected and handled.

MODE="dry-run"
MAX_ITERATIONS=5
ITERATION=0
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --confirm)
            MODE="confirm"
            shift
            ;;
        --max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [--confirm] [--max-iterations N]

Autonomous test-detect-fix loop for the AltOS installer.

Options:
  --confirm            Run in confirm mode (potentially destructive).
                       Requires manual confirmation.
  --max-iterations N   Maximum number of fix iterations (default: 5)
  --help, -h           Show this help message

Examples:
  $0                          # Default dry-run loop
  $0 --max-iterations 10      # Up to 10 iterations in dry-run mode
  $0 --confirm                # Live confirm mode (DANGEROUS)
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--confirm] [--max-iterations N]" >&2
            exit 1
            ;;
    esac
done

mkdir -p /tmp/altos-tests

echo "=== AltOS Agent Loop ==="
echo "Tools directory: $TOOLS_DIR"
echo "Mode: $MODE"
echo "Max iterations: $MAX_ITERATIONS"
echo ""

# ------------------------------------------------------------------
# Safety check for confirm mode
# ------------------------------------------------------------------
if [[ "$MODE" == "confirm" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " WARNING: confirm mode will run the ACTUAL installer."
    echo " Only use this in a safe, disposable environment"
    echo " (e.g., an Arch Live ISO virtual machine)."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -r -p "Type 'CONFIRM' to proceed: " CONFIRM_INPUT
    if [[ "$CONFIRM_INPUT" != "CONFIRM" ]]; then
        echo "Aborted."
        exit 1
    fi
    echo ""
fi

# ------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------
while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
    ITERATION=$((ITERATION + 1))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Iteration $ITERATION / $MAX_ITERATIONS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ---- Step 1: Run test ----------------------------------------
    echo ""
    echo "[1/3] Running test (mode: $MODE)..."
    TEST_LOG="/tmp/altos-tests/loop-run-$ITERATION.log"

    set +e
    "$TOOLS_DIR/run-test.sh" "$MODE" > "$TEST_LOG" 2>&1
    TEST_EXIT=$?
    set -e

    if [[ $TEST_EXIT -eq 0 ]]; then
        echo ""
        echo "[PASS] Test passed. No errors detected."
        echo "Log: $TEST_LOG"
        exit 0
    fi

    echo "[FAIL] Test failed (exit $TEST_EXIT)."

    # ---- Step 2: Detect error ------------------------------------
    echo ""
    echo "[2/3] Detecting error..."
    DETECT_RESULT=$("$TOOLS_DIR/detect-error.sh" 2>/dev/null || echo '{"error_type":"unknown","confidence":0}')
    echo "$DETECT_RESULT"

    ERROR_TYPE=$(echo "$DETECT_RESULT" | grep -o '"error_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"error_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    CONFIDENCE=$(echo "$DETECT_RESULT" | grep -o '"confidence"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"confidence"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' || echo "0")

    if [[ -z "$ERROR_TYPE" || "$ERROR_TYPE" == "unknown" ]]; then
        echo ""
        echo "[STOP] Could not classify error. Manual investigation required."
        echo "Test log: $TEST_LOG"
        exit 1
    fi

    echo ""
    echo "Detected error: $ERROR_TYPE (confidence: $CONFIDENCE%)"

    # ---- Step 3: Apply fix ---------------------------------------
    echo ""
    echo "[3/3] Applying fix for $ERROR_TYPE..."
    APPLY_LOG="/tmp/altos-tests/loop-fix-$ITERATION.log"

    set +e
    "$TOOLS_DIR/apply-fix.sh" "$ERROR_TYPE" "--$MODE" > "$APPLY_LOG" 2>&1
    APPLY_EXIT=$?
    set -e

    cat "$APPLY_LOG"

    FIX_APPLIED=$(grep -o '"fix_applied"[[:space:]]*:[[:space:]]*true' "$APPLY_LOG" || true)
    VALIDATION_STATUS=$(grep -o '"validation_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$APPLY_LOG" | sed 's/.*"validation_status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "not_run")

    if [[ -z "$FIX_APPLIED" ]]; then
        echo ""
        echo "[STOP] Fix could not be applied automatically for: $ERROR_TYPE"
        echo "Apply-fix log: $APPLY_LOG"
        exit 1
    fi

    echo ""
    echo "[OK] Fix applied."

    if [[ "$VALIDATION_STATUS" == "pass" ]]; then
        echo "[PASS] Validation passed. Fix resolved the issue."
        exit 0
    elif [[ "$VALIDATION_STATUS" == "fail" ]]; then
        echo "[INFO] Validation failed. Will attempt next iteration..."
    else
        echo "[INFO] Fix applied without validation. Continuing loop..."
    fi

    echo ""
done

echo ""
echo "[STOP] Reached maximum iterations ($MAX_ITERATIONS) without resolving the issue."
exit 1

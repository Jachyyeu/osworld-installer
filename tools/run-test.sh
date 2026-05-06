#!/bin/bash
# Usage: ./run-test.sh [mode]
# mode: dry-run (default) or confirm

set -euo pipefail

MODE="${1:-dry-run}"
LOG_DIR="/tmp/altos-tests"
LOG_FILE="$LOG_DIR/test-$(date +%s).log"
RESULT_FILE="$LOG_DIR/latest-result.json"

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$TOOLS_DIR/../scripts/installer"

mkdir -p "$LOG_DIR"

echo "=== AltOS Test Run ===" | tee "$LOG_FILE"
echo "Mode: $MODE" | tee -a "$LOG_FILE"
echo "Time: $(date)" | tee -a "$LOG_FILE"
echo "Installer: $INSTALLER_DIR" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

cd "$INSTALLER_DIR"

if ./install.sh "--$MODE" 2>&1 | tee -a "$LOG_FILE"; then
    STATUS="PASS"
    EXIT_CODE=0
else
    STATUS="FAIL"
    EXIT_CODE=$?
fi

# Write structured result
cat > "$RESULT_FILE" << EOF
{
    "status": "$STATUS",
    "exit_code": $EXIT_CODE,
    "log_file": "$LOG_FILE",
    "timestamp": "$(date -Iseconds)",
    "mode": "$MODE"
}
EOF

echo "" | tee -a "$LOG_FILE"
echo "=== Result: $STATUS (exit $EXIT_CODE) ===" | tee -a "$LOG_FILE"

cat "$RESULT_FILE"

if [ "$STATUS" = "PASS" ]; then
    exit 0
else
    exit 1
fi

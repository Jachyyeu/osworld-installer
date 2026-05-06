#!/bin/bash
# Usage: ./detect-error.sh [log_file]
# Analyzes a test log and classifies the error.
# If no log_file is provided, reads from /tmp/altos-tests/latest-result.json.

set -euo pipefail

LOG_FILE="${1:-}"

# Resolve log file
if [[ -z "$LOG_FILE" ]]; then
    LATEST_RESULT="/tmp/altos-tests/latest-result.json"
    if [[ -f "$LATEST_RESULT" ]]; then
        # Extract log_file field without jq
        LOG_FILE=$(grep -o '"log_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$LATEST_RESULT" | sed 's/.*"log_file"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
fi

if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    cat <<EOF
{
    "error_type": "unknown",
    "description": "No log file specified and no latest result found.",
    "suggested_fix": "Run run-test.sh first, or provide a log file path.",
    "confidence": 0,
    "log_file": null
}
EOF
    exit 1
fi

# Error detection patterns (checked in priority order)
ERROR_TYPE="unknown"
DESCRIPTION="No recognized error pattern found."
SUGGESTED_FIX="Review the log manually."
CONFIDENCE=0
DETAILS=""

# 1. Permission denied
if grep -q "must be run as root" "$LOG_FILE"; then
    ERROR_TYPE="permission_denied"
    DESCRIPTION="The installer requires root privileges (EUID != 0)."
    SUGGESTED_FIX="Run the test with sudo, or modify install.sh to skip the root check when DRY_RUN=true."
    CONFIDENCE=95

# 2. Missing config file
elif grep -q "Configuration file not found" "$LOG_FILE"; then
    ERROR_TYPE="missing_config"
    DESCRIPTION="The installer expects /tmp/install-config.json but it does not exist."
    SUGGESTED_FIX="Create a minimal valid configuration file at /tmp/install-config.json."
    CONFIDENCE=95

# 3. Bad config content
elif grep -q "target_disk is not set" "$LOG_FILE"; then
    ERROR_TYPE="bad_config"
    DESCRIPTION="Configuration file exists but target_disk is missing or empty."
    SUGGESTED_FIX="Patch the configuration file to include a valid target_disk field."
    CONFIDENCE=95

# 4. UEFI not detected
elif grep -q "UEFI mode not detected" "$LOG_FILE"; then
    ERROR_TYPE="uefi_not_detected"
    DESCRIPTION="The system is not booted in UEFI mode."
    SUGGESTED_FIX="Boot in UEFI mode, or modify the installer to skip UEFI checks in dry-run / test environments."
    CONFIDENCE=90

# 5. No network
elif grep -q "Internet connection not detected" "$LOG_FILE"; then
    ERROR_TYPE="no_network"
    DESCRIPTION="No internet connection detected (cannot reach archlinux.org)."
    SUGGESTED_FIX="Check network connectivity, or mock the network check in the installer for offline testing."
    CONFIDENCE=90

# 6. Disk mounted
elif grep -q "is currently mounted" "$LOG_FILE"; then
    ERROR_TYPE="disk_mounted"
    DESCRIPTION="The target disk or one of its partitions is currently mounted."
    SUGGESTED_FIX="Unmount the target disk, or select a different disk in the configuration."
    CONFIDENCE=90

# 7. Partitioning failure
elif grep -q "Could not find all required partitions" "$LOG_FILE"; then
    ERROR_TYPE="disk_partition_error"
    DESCRIPTION="Partitioning step failed to create expected partitions."
    SUGGESTED_FIX="Review disk.sh partitioning logic and ensure the target disk is unmounted and accessible."
    CONFIDENCE=85

# 8. Missing command / dependency
elif grep -qi "command not found" "$LOG_FILE"; then
    ERROR_TYPE="command_not_found"
    DESCRIPTION="A required command is missing on the system."
    SUGGESTED_FIX="Install the missing package, or add it to the test environment setup."
    CONFIDENCE=85
    MISSING_CMD=$(grep -oi "command not found:[[:space:]]*[a-z0-9_-]*" "$LOG_FILE" | head -n 1 | sed 's/.*:[[:space:]]*//' || true)
    if [[ -n "$MISSING_CMD" ]]; then
        DETAILS="Missing command: $MISSING_CMD"
    fi

# 9. Bash syntax errors
elif grep -qiE "syntax error|unexpected|unexpected end of file|bad substitution" "$LOG_FILE"; then
    ERROR_TYPE="syntax_error"
    DESCRIPTION="Bash syntax error detected in the installer or a sourced library."
    SUGGESTED_FIX="Review the reported file and line number in the test log, then fix the syntax error."
    CONFIDENCE=80
    DETAILS=$(grep -inE "syntax error|unexpected|unexpected end of file|bad substitution" "$LOG_FILE" | head -n 3 | sed 's/"/\\"/g' | tr '\n' '; ')

# 10. Python / JSON parse error (config related)
elif grep -qiE "json\.decoder\.|json\.jsondecodeerror|valueerror|keyerror" "$LOG_FILE"; then
    ERROR_TYPE="bad_config"
    DESCRIPTION="Configuration file could not be parsed as valid JSON."
    SUGGESTED_FIX="Validate and repair the JSON syntax in /tmp/install-config.json."
    CONFIDENCE=85
fi

# Build JSON output
DETAILS_JSON="null"
if [[ -n "$DETAILS" ]]; then
    DETAILS_JSON="\"$DETAILS\""
fi

cat <<EOF
{
    "error_type": "$ERROR_TYPE",
    "description": "$DESCRIPTION",
    "suggested_fix": "$SUGGESTED_FIX",
    "confidence": $CONFIDENCE,
    "log_file": "$LOG_FILE",
    "details": $DETAILS_JSON
}
EOF

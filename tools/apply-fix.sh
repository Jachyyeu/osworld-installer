#!/bin/bash
# Usage: ./apply-fix.sh <error_type> [--dry-run|--confirm]
# Applies a fix for the given error type and optionally validates it.

set -uo pipefail
# -e is disabled because validation re-runs may fail, and we handle exit codes explicitly

ERROR_TYPE="${1:-}"
MODE="${2:---dry-run}"

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TOOLS_DIR")"
INSTALLER_DIR="$PROJECT_DIR/scripts/installer"

if [[ -z "$ERROR_TYPE" ]]; then
    cat <<EOF
{
    "status": "error",
    "message": "No error_type specified. Usage: ./apply-fix.sh <error_type> [--dry-run|--confirm]"
}
EOF
    exit 1
fi

DRY_RUN=true
if [[ "$MODE" == "--confirm" ]]; then
    DRY_RUN=false
fi

FIX_APPLIED="false"
FIX_DETAILS=""
VALIDATION_STATUS="not_run"

# ------------------------------------------------------------------
# Fix implementations
# ------------------------------------------------------------------
case "$ERROR_TYPE" in
    missing_config)
        CONFIG_FILE="/tmp/install-config.json"
        FIX_DETAILS="Created minimal valid config at $CONFIG_FILE"
        if [[ "$DRY_RUN" == false ]]; then
            cat > "$CONFIG_FILE" <<'CONFIG'
{
    "target_disk": "/dev/sda",
    "mode": "wipe",
    "hostname": "altos-test",
    "username": "testuser",
    "password": "testpass123",
    "timezone": "UTC",
    "locale": "en_US.UTF-8",
    "keymap": "us"
}
CONFIG
            FIX_APPLIED="true"
        else
            FIX_DETAILS="[DRY] Would create minimal config at $CONFIG_FILE"
        fi
        ;;

    bad_config)
        CONFIG_FILE="/tmp/install-config.json"
        FIX_DETAILS="Patched config to include target_disk"
        if [[ "$DRY_RUN" == false ]]; then
            if [[ -f "$CONFIG_FILE" ]]; then
                if ! grep -q '"target_disk"' "$CONFIG_FILE"; then
                    # Use Python because install.sh already depends on it for JSON parsing
                    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        cfg = json.load(f)
    cfg.setdefault('target_disk', '/dev/sda')
    cfg.setdefault('mode', 'wipe')
    cfg.setdefault('hostname', 'altos-test')
    cfg.setdefault('username', 'testuser')
    cfg.setdefault('password', 'testpass123')
    cfg.setdefault('timezone', 'UTC')
    cfg.setdefault('locale', 'en_US.UTF-8')
    cfg.setdefault('keymap', 'us')
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(cfg, f, indent=4)
except Exception as e:
    print(f'Error patching config: {e}', file=sys.stderr)
    sys.exit(1)
"
                    FIX_APPLIED="true"
                else
                    FIX_DETAILS="target_disk already present; checking other required fields..."
                    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        cfg = json.load(f)
    required = {'target_disk':'/dev/sda','mode':'wipe','hostname':'altos-test','username':'testuser','password':'testpass123','timezone':'UTC','locale':'en_US.UTF-8','keymap':'us'}
    changed = False
    for k, v in required.items():
        if k not in cfg or not cfg[k]:
            cfg[k] = v
            changed = True
    if changed:
        with open('$CONFIG_FILE', 'w') as f:
            json.dump(cfg, f, indent=4)
        print('Patched missing fields.')
    else:
        print('All required fields present.')
except Exception as e:
    print(f'Error patching config: {e}', file=sys.stderr)
    sys.exit(1)
"
                    FIX_APPLIED="true"
                fi
            else
                FIX_DETAILS="Config file not found, falling back to missing_config fix"
                cat > "$CONFIG_FILE" <<'CONFIG'
{
    "target_disk": "/dev/sda",
    "mode": "wipe",
    "hostname": "altos-test",
    "username": "testuser",
    "password": "testpass123",
    "timezone": "UTC",
    "locale": "en_US.UTF-8",
    "keymap": "us"
}
CONFIG
                FIX_APPLIED="true"
            fi
        else
            FIX_DETAILS="[DRY] Would patch config at $CONFIG_FILE"
        fi
        ;;

    permission_denied)
        FIX_DETAILS="Cannot auto-fix permission denied. Suggestion: run tests with sudo, or patch install.sh verify_environment() to skip root check when DRY_RUN=true."
        ;;

    uefi_not_detected)
        FIX_DETAILS="Cannot auto-fix UEFI detection (hardware/environment issue). Suggestion: mock UEFI check in install.sh for testing, or run inside a UEFI-enabled VM."
        ;;

    no_network)
        FIX_DETAILS="Cannot auto-fix network connectivity. Suggestion: mock the ping check in install.sh for offline testing, or ensure the test host has internet access."
        ;;

    disk_mounted)
        FIX_DETAILS="Cannot safely auto-fix mounted disk. Suggestion: unmount the target disk manually, or change target_disk in config to an unmounted device."
        ;;

    disk_partition_error)
        FIX_DETAILS="Cannot safely auto-fix disk partitioning errors. Suggestion: review disk.sh logic and verify the test environment provides a clean, unmounted block device."
        ;;

    command_not_found)
        # Try to identify the missing command from the latest log
        LOG_FILE=""
        LATEST_RESULT="/tmp/altos-tests/latest-result.json"
        if [[ -f "$LATEST_RESULT" ]]; then
            LOG_FILE=$(grep -o '"log_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$LATEST_RESULT" | sed 's/.*"log_file"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        MISSING_CMD=""
        if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
            MISSING_CMD=$(grep -oi "command not found:[[:space:]]*[a-z0-9_-]*" "$LOG_FILE" | head -n 1 | sed 's/.*:[[:space:]]*//' || true)
        fi
        if [[ -n "$MISSING_CMD" ]]; then
            FIX_DETAILS="Missing command detected: $MISSING_CMD. Install the corresponding package or mock the command for testing."
        else
            FIX_DETAILS="Missing command detected but could not identify which one. Check the test log for 'command not found'."
        fi
        ;;

    syntax_error)
        FIX_DETAILS="Syntax errors require manual code review. Check the test log for the exact file and line number, then edit the script directly."
        LOG_FILE=""
        LATEST_RESULT="/tmp/altos-tests/latest-result.json"
        if [[ -f "$LATEST_RESULT" ]]; then
            LOG_FILE=$(grep -o '"log_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$LATEST_RESULT" | sed 's/.*"log_file"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
            SYNTAX_LINES=$(grep -inE "syntax error|unexpected|unexpected end of file|bad substitution" "$LOG_FILE" | head -n 3 | sed 's/"/\\"/g' | tr '\n' '; ')
            if [[ -n "$SYNTAX_LINES" ]]; then
                FIX_DETAILS="$FIX_DETAILS Details: $SYNTAX_LINES"
            fi
        fi
        ;;

    *)
        FIX_DETAILS="Unknown error type: $ERROR_TYPE. No automated fix is available."
        ;;
esac

# ------------------------------------------------------------------
# Validation: re-run the test in dry-run mode to see if the fix worked
# ------------------------------------------------------------------
if [[ "$DRY_RUN" == false && "$FIX_APPLIED" == "true" ]]; then
    echo "Validating fix by re-running test in dry-run mode..." >&2
    VALIDATION_LOG="/tmp/altos-tests/validation-$(date +%s).log"
    set +e
    "$TOOLS_DIR/run-test.sh" dry-run > "$VALIDATION_LOG" 2>&1
    VALIDATION_EXIT=$?
    set -e

    if [[ $VALIDATION_EXIT -eq 0 ]]; then
        VALIDATION_STATUS="pass"
    else
        VALIDATION_STATUS="fail"
    fi
fi

cat <<EOF
{
    "status": "ok",
    "error_type": "$ERROR_TYPE",
    "fix_applied": $FIX_APPLIED,
    "mode": "$MODE",
    "fix_details": "$FIX_DETAILS",
    "validation_status": "$VALIDATION_STATUS"
}
EOF

if [[ "$VALIDATION_STATUS" == "pass" ]]; then
    exit 0
elif [[ "$VALIDATION_STATUS" == "fail" ]]; then
    exit 1
else
    exit 0
fi

#!/bin/bash
set -euo pipefail

# ============================================================
# lib/logging.sh — Universal error logging for AltOS installer
# Designed to be sourced by install.sh
# Logs to both /tmp/altos-install.log (Live env) and
# /mnt/install.log (target system, when /mnt is mounted).
# ============================================================

# --- Colors (self-contained for independent testing) --------
if [[ -z "${GREEN:-}" ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
fi

# --- Log file paths -----------------------------------------
LOG_FILE_LIVE="/tmp/altos-install.log"
LOG_FILE_TARGET="/mnt/install.log"
CRASH_REPORT="/tmp/altos-crash-report.txt"

# --- Crash report on failure --------------------------------
_copy_crash_report() {
  local exit_code=$?
  if [[ "$exit_code" -ne 0 && -f "$LOG_FILE_LIVE" ]]; then
    cp "$LOG_FILE_LIVE" "$CRASH_REPORT"
    echo -e "${RED}[FAIL] Installation failed with exit code ${exit_code}.${RESET}" | tee -a "$LOG_FILE_LIVE"
    echo -e "${RED}[FAIL] Crash report copied to: ${CRASH_REPORT}${RESET}" | tee -a "$LOG_FILE_LIVE"
  fi
}
trap _copy_crash_report EXIT

# --- Internal helpers ---------------------------------------
_log_write() {
  local msg="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local line="[${timestamp}] ${msg}"

  # Always write to live log
  echo "$line" >> "$LOG_FILE_LIVE"

  # Also write to target system log if /mnt is mounted
  if mountpoint -q /mnt 2>/dev/null; then
    echo "$line" >> "$LOG_FILE_TARGET"
  fi
}

# --- Public API ---------------------------------------------

log_start() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${BLUE}[INFO] Logging started at ${timestamp}${RESET}"

  # Ensure live log exists
  touch "$LOG_FILE_LIVE"
  echo "========================================" >> "$LOG_FILE_LIVE"
  echo "AltOS Installer Log — ${timestamp}" >> "$LOG_FILE_LIVE"
  echo "========================================" >> "$LOG_FILE_LIVE"

  # Pre-create target log if /mnt is already mounted
  if mountpoint -q /mnt 2>/dev/null; then
    touch "$LOG_FILE_TARGET"
    echo "========================================" >> "$LOG_FILE_TARGET"
    echo "AltOS Installer Log — ${timestamp}" >> "$LOG_FILE_TARGET"
    echo "========================================" >> "$LOG_FILE_TARGET"
  fi
}

log_info() {
  local msg="$1"
  _log_write "[INFO] ${msg}"
  echo -e "${BLUE}[INFO] ${msg}${RESET}"
}

log_error() {
  local msg="$1"
  _log_write "[ERROR] ${msg}"
  echo -e "${RED}[ERROR] ${msg}${RESET}"
}

log_warn() {
  local msg="$1"
  _log_write "[WARN] ${msg}"
  echo -e "${YELLOW}[WARN] ${msg}${RESET}"
}

log_ok() {
  local msg="$1"
  _log_write "[OK] ${msg}"
  echo -e "${GREEN}[OK] ${msg}${RESET}"
}

# Wrap any command: logs the command, runs it, captures stdout+stderr,
# logs result.  Respects DRY_RUN.
log_cmd() {
  local cmd_str="$*"
  _log_write "[RUN] ${cmd_str}"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    _log_write "[DRY] Would run: ${cmd_str}"
    echo -e "${BLUE}[DRY] Would: ${cmd_str}${RESET}"
    return 0
  fi

  echo -e "${GREEN}[OK] Running: ${cmd_str}${RESET}"

  local tmpfile
  tmpfile=$(mktemp)

  # Run command, streaming to terminal while capturing to temp file
  {
    "$@" 2>&1
  } | tee "$tmpfile"
  local exit_code=${PIPESTATUS[0]}

  # Append captured output to log files
  if [[ -s "$tmpfile" ]]; then
    while IFS= read -r line; do
      _log_write "[OUT] ${line}"
    done < "$tmpfile"
  fi
  rm -f "$tmpfile"

  if [[ "$exit_code" -ne 0 ]]; then
    _log_write "[FAIL] Exit code ${exit_code}: ${cmd_str}"
    echo -e "${RED}[FAIL] Command failed (${exit_code}): ${cmd_str}${RESET}"
    return "$exit_code"
  else
    _log_write "[OK] Completed: ${cmd_str}"
    return 0
  fi
}

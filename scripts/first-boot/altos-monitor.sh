#!/bin/bash
set -euo pipefail

# ============================================================
# altos-monitor.sh — Optional remote monitoring for first boot
# Takes screenshots periodically and uploads them via scp.
# Designed to run as a systemd user service after graphical login.
# ============================================================

CONFIG_FILE="/etc/altos/monitor.conf"
DONE_FLAG="$HOME/.config/altos/first-boot-done"
INTERVAL_SECS="${ALTOS_MONITOR_INTERVAL:-30}"
DEST_HOST="${ALTOS_MONITOR_HOST:-}"
DEST_USER="${ALTOS_MONITOR_USER:-}"
DEST_PATH="${ALTOS_MONITOR_PATH:-}"

# --- Read config file if present ---
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# --- Validate config ---
if [[ -z "$DEST_HOST" || -z "$DEST_USER" || -z "$DEST_PATH" ]]; then
  echo "[altos-monitor] Remote monitoring not configured. Set ALTOS_MONITOR_HOST/USER/PATH or create ${CONFIG_FILE}."
  exit 0
fi

# --- Ensure ssh key exists ---
SSH_KEY="$HOME/.ssh/altos_monitor"
if [[ ! -f "$SSH_KEY" ]]; then
  echo "[altos-monitor] SSH key not found at ${SSH_KEY}. Skipping."
  exit 0
fi

# --- Take and upload screenshots ---
SHOT_DIR="/tmp/altos-screenshots"
mkdir -p "$SHOT_DIR"

upload_shot() {
  local file="$1"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local dest="${DEST_PATH}/altos_${HOSTNAME}_${timestamp}.png"
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$file" "${DEST_USER}@${DEST_HOST}:${dest}" 2>/dev/null || true
  rm -f "$file"
}

echo "[altos-monitor] Starting screenshot loop (every ${INTERVAL_SECS}s) → ${DEST_USER}@${DEST_HOST}:${DEST_PATH}"

while [[ ! -f "$DONE_FLAG" ]]; do
  TIMESTAMP=$(date +%s)
  SHOT_FILE="${SHOT_DIR}/shot_${TIMESTAMP}.png"

  # Try grim for Wayland, then spectacle for KDE, then skip
  if command -v grim &>/dev/null; then
    grim "$SHOT_FILE" 2>/dev/null || true
  elif command -v spectacle &>/dev/null; then
    spectacle -b -n -o "$SHOT_FILE" 2>/dev/null || true
  else
    echo "[altos-monitor] No screenshot tool available (install grim or spectacle)."
    exit 0
  fi

  if [[ -f "$SHOT_FILE" ]]; then
    upload_shot "$SHOT_FILE"
  fi

  sleep "$INTERVAL_SECS"
done

echo "[altos-monitor] First-boot wizard completed. Stopping monitor."

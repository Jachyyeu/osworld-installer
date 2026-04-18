#!/bin/bash
set -euo pipefail

# ============================================================
# live-bridge.sh — Arch Live ISO bridge script
# Automatically mounts the OSWORLDBOOT partition, copies the
# staged install-config.json, and hands off to install.sh.
# Usage:
#   sudo bash live-bridge.sh --dry-run
#   sudo bash live-bridge.sh --confirm
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors -------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# --- Safety -------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}[FAIL] This script must be run as root (use sudo).${RESET}"
  exit 1
fi

echo -e "${BLUE}[INFO] OSWorld Live Bridge starting...${RESET}"

# --- Find OSWORLDBOOT partition -----------------------------
echo -e "${BLUE}[INFO] Searching for partition labeled OSWORLDBOOT...${RESET}"

OSWORLD_DEV=""
if command -v findfs &>/dev/null; then
  OSWORLD_DEV=$(findfs LABEL=OSWORLDBOOT 2>/dev/null || true)
fi

if [[ -z "${OSWORLD_DEV:-}" ]]; then
  OSWORLD_DEV=$(blkid -L OSWORLDBOOT 2>/dev/null || true)
fi

if [[ -z "${OSWORLD_DEV:-}" ]]; then
  echo -e "${RED}[FAIL] Could not find any partition labeled OSWORLDBOOT.${RESET}"
  echo -e "${RED}[FAIL] Make sure the Windows staging completed successfully.${RESET}"
  exit 1
fi

echo -e "${GREEN}[OK] Found OSWORLDBOOT at ${OSWORLD_DEV}${RESET}"

# --- Mount and copy config ----------------------------------
MOUNT_POINT="/mnt/osworldboot"

mkdir -p "$MOUNT_POINT"

echo -e "${BLUE}[INFO] Mounting ${OSWORLD_DEV} to ${MOUNT_POINT}...${RESET}"
mount "$OSWORLD_DEV" "$MOUNT_POINT"
echo -e "${GREEN}[OK] Mounted.${RESET}"

STAGED_CONFIG="${MOUNT_POINT}/install-config.json"

if [[ ! -f "$STAGED_CONFIG" ]]; then
  echo -e "${RED}[FAIL] ${STAGED_CONFIG} not found on OSWORLDBOOT partition.${RESET}"
  echo -e "${YELLOW}[WARN] The Windows app should have written this file during staging.${RESET}"
  umount "$MOUNT_POINT" || true
  exit 1
fi

echo -e "${BLUE}[INFO] Copying install-config.json to /tmp/install-config.json...${RESET}"
cp "$STAGED_CONFIG" /tmp/install-config.json

echo -e "${BLUE}[INFO] Validating JSON...${RESET}"
if ! python3 -c "import json; json.load(open('/tmp/install-config.json'))" 2>/dev/null; then
  echo -e "${RED}[FAIL] /tmp/install-config.json is not valid JSON.${RESET}"
  umount "$MOUNT_POINT" || true
  exit 1
fi

echo -e "${GREEN}[OK] Config copied and validated.${RESET}"

echo -e "${BLUE}[INFO] Unmounting ${MOUNT_POINT}...${RESET}"
umount "$MOUNT_POINT"
echo -e "${GREEN}[OK] Unmounted.${RESET}"

# --- Hand off to install.sh ---------------------------------
echo -e "${BLUE}[INFO] Handing off to install.sh...${RESET}"
echo ""

exec "$SCRIPT_DIR/install.sh" "$@"

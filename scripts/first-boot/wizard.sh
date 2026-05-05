#!/bin/bash
set -euo pipefail

# ============================================================
# wizard.sh — AltOS First-Boot Wizard
# Runs after first login to guide the user through setup.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEPS_DIR="$SCRIPT_DIR/steps"
DONE_FLAG="$HOME/.config/altos/first-boot-done"

# --- Colors -------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

print_banner() {
  clear
  echo -e "${CYAN}"
  echo '    ___    __    _____            __ '
  echo '   /   |  / /   / ___/____ ______/ /_'
  echo '  / /| | / /    \__ \/ __ `/ ___/ __/'
  echo ' / ___ |/ /    ___/ / /_/ (__  ) /_  '
  echo '/_/  |_/_/    /____/\__,_/____/\__/  '
  echo -e "${RESET}"
  echo -e "${BLUE}=======================================${RESET}"
  echo -e "${BLUE}  Welcome to AltOS. Let's get you set up.${RESET}"
  echo -e "${BLUE}=======================================${RESET}"
  echo ""
}

ask_yesno() {
  local prompt="$1"
  local default="${2:-Y}"
  local answer
  while true; do
    read -rp "$(echo -e "${BLUE}[?]${RESET} $prompt [Y/n]: ")" answer
    answer="${answer:-$default}"
    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo -e "${YELLOW}[WARN] Please answer Y or n.${RESET}" ;;
    esac
  done
}

ask_skip() {
  local step_name="$1"
  if ask_yesno "Run '$step_name'?" "Y"; then
    return 0
  else
    echo -e "${YELLOW}[SKIP] Skipping $step_name.${RESET}"
    return 1
  fi
}

run_step() {
  local script="$1"
  local name="$2"
  if [[ -x "$script" ]]; then
    echo -e "${BLUE}[INFO] Running: $name...${RESET}"
    if "$script"; then
      echo -e "${GREEN}[OK] $name completed.${RESET}"
    else
      echo -e "${YELLOW}[WARN] $name exited with an error (non-fatal).${RESET}"
    fi
  else
    echo -e "${YELLOW}[WARN] Step script not found or not executable: $script${RESET}"
  fi
  echo ""
}

# --- Main ---------------------------------------------------
main() {
  # Check if already run
  if [[ -f "$DONE_FLAG" ]]; then
    echo -e "${GREEN}[OK] First-boot wizard already completed.${RESET}"
    echo -e "${BLUE}[INFO] To run again, delete: $DONE_FLAG${RESET}"
    exit 0
  fi

  print_banner

  # Ensure steps directory exists
  if [[ ! -d "$STEPS_DIR" ]]; then
    echo -e "${RED}[FAIL] Steps directory not found: $STEPS_DIR${RESET}"
    exit 1
  fi

  # Step 1: Import from Windows (dualboot only)
  if ask_skip "Import from Windows"; then
    run_step "$STEPS_DIR/import-windows.sh" "Windows Import"
  fi

  # Step 2: Pick theme
  if ask_skip "Pick your desktop theme"; then
    run_step "$STEPS_DIR/pick-theme.sh" "Theme Selection"
  fi

  # Step 3: Setup recommended apps
  if ask_skip "Install recommended apps"; then
    run_step "$STEPS_DIR/setup-apps.sh" "App Installation"
  fi

  # Step 4: Finalize
  run_step "$STEPS_DIR/finalize.sh" "Finalization"

  echo ""
  echo -e "${GREEN}=======================================${RESET}"
  echo -e "${GREEN}  First-boot setup complete!${RESET}"
  echo -e "${GREEN}=======================================${RESET}"
}

main "$@"

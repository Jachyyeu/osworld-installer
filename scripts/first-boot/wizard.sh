#!/bin/bash
set -euo pipefail

# ============================================================
# wizard.sh — AltOS First-Boot Wizard launcher
# Launches the graphical PyQt6 wizard on first login.
# Falls back to the terminal-based steps if the GUI cannot start.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DONE_FLAG="$HOME/.config/altos/first-boot-done"

# --- Colors (fallback mode only) ---------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# --- Already done? -----------------------------------------
if [[ -f "$DONE_FLAG" ]]; then
  exit 0
fi

# --- Launch GUI wizard --------------------------------------
GUI_SCRIPT="${SCRIPT_DIR}/wizard_gui.py"

launch_gui() {
  # Ensure PyQt6 is available
  if ! python3 -c "import PyQt6" 2>/dev/null; then
    return 1
  fi

  # Run the wizard
  if [[ -x "$GUI_SCRIPT" ]]; then
    exec python3 "$GUI_SCRIPT"
  else
    python3 "$GUI_SCRIPT"
  fi
}

# --- Fallback: terminal wizard -----------------------------
run_fallback() {
  echo -e "${YELLOW}[WARN] Could not launch graphical wizard.${RESET}"
  echo -e "${BLUE}[INFO] Falling back to terminal-based setup...${RESET}"
  echo ""

  STEPS_DIR="$SCRIPT_DIR/steps"

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
      echo -e "${YELLOW}[WARN] Step script not found: $script${RESET}"
    fi
    echo ""
  }

  # Import
  read -rp "$(echo -e "${BLUE}[?]${RESET} Import from Windows? [y/N]: ")" answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    run_step "$STEPS_DIR/import-windows.sh" "Windows Import"
  fi

  # Theme
  read -rp "$(echo -e "${BLUE}[?]${RESET} Pick desktop theme? [y/N]: ")" answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    run_step "$STEPS_DIR/pick-theme.sh" "Theme Selection"
  fi

  # Apps
  read -rp "$(echo -e "${BLUE}[?]${RESET} Install recommended apps? [y/N]: ")" answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    run_step "$STEPS_DIR/setup-apps.sh" "App Installation"
  fi

  # Finalize
  run_step "$STEPS_DIR/finalize.sh" "Finalization"
}

# --- Main ---------------------------------------------------
if ! launch_gui; then
  run_fallback
fi

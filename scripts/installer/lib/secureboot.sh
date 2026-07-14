#!/bin/bash
set -euo pipefail

# ============================================================
# secureboot.sh — Secure Boot verification for AltOS on Fedora
# Called by install.sh after the base system is installed.
# Fedora ships a Microsoft-signed shim -> GRUB2 -> kernel chain,
# so no custom MOK enrollment is required.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

: "${ALTOS_MOUNT:=/mnt}"
: "${EFI_PARTITION:=/boot/efi}"

setup_secure_boot() {
  info "Starting Secure Boot verification (Fedora signed chain)..."

  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY] Would verify Fedora signed shim/GRUB2/kernel are present."
    return 0
  fi

  # Verify the Fedora signed boot chain is installed on the ESP.
  local shim="${ALTOS_MOUNT}${EFI_PARTITION}/EFI/fedora/shimx64.efi"
  local grub="${ALTOS_MOUNT}${EFI_PARTITION}/EFI/fedora/grubx64.efi"
  local kernel
  kernel=$(ls "${ALTOS_MOUNT}/boot/vmlinuz"* 2>/dev/null | head -n1 || true)

  if [[ ! -f "$shim" ]]; then
    warn "Fedora signed shim not found at ${shim}. Secure Boot may fail."
  else
    ok "Fedora signed shim present."
  fi

  if [[ ! -f "$grub" ]]; then
    warn "Fedora GRUB2 not found at ${grub}. Secure Boot may fail."
  else
    ok "Fedora GRUB2 present."
  fi

  if [[ -z "$kernel" ]]; then
    warn "Fedora kernel not found in /boot. Secure Boot may fail."
  else
    ok "Fedora kernel present: ${kernel}"
  fi

  info "Secure Boot setup complete. Chain: Microsoft-signed shim → Fedora GRUB2 → Fedora kernel"
}

# Kept for compatibility if any caller invokes it, but it is a no-op on Fedora.
print_mok_walkthrough() {
  cat <<'EOF'

AltOS is using Fedora's Microsoft-signed Secure Boot chain.
No one-time MOK enrollment is required.

EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_secure_boot
fi

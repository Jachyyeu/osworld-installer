#!/bin/bash
set -uo pipefail

# End-to-end VM test: UEFI ISO install + reboot from disk

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="/home/jachyyeu/osworld-installer/out/altos-2026.06.12-x86_64.iso"
DISK="$SCRIPT_DIR/target-disk.img"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
INSTALL_LOG="$SCRIPT_DIR/serial.log"
REBOOT_LOG="$SCRIPT_DIR/reboot-test.log"

if [[ ! -f "$ISO" ]]; then
  echo "[FAIL] ISO not found: $ISO"
  exit 1
fi
if [[ ! -f "$DISK" ]]; then
  echo "[FAIL] Disk image not found: $DISK"
  exit 1
fi

# Clean up any leftover QEMU
if [[ -f "$SCRIPT_DIR/qemu.pid" ]]; then
  pid=$(cat "$SCRIPT_DIR/qemu.pid" 2>/dev/null) || true
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    sleep 2
  fi
fi

# --- Phase 1: Install from ISO via UEFI ---
cp "$OVMF_VARS" "$SCRIPT_DIR/ovmf_vars.fd"
rm -f "$INSTALL_LOG"

echo "[INFO] Phase 1: UEFI install from ISO..."
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -cpu host \
  -cdrom "$ISO" \
  -drive file="$DISK",format=raw,if=virtio \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$SCRIPT_DIR/ovmf_vars.fd" \
  -serial file:"$INSTALL_LOG" \
  -display none \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  > "$SCRIPT_DIR/e2e-install-nohup.out" 2>&1 &

INSTALL_PID=$!
echo "$INSTALL_PID" > "$SCRIPT_DIR/qemu.pid"
echo "[INFO] Install QEMU PID: $INSTALL_PID"

install_ok=false
install_timeout=900
install_elapsed=0
while [[ $install_elapsed -lt $install_timeout ]]; do
  sleep 10
  install_elapsed=$((install_elapsed + 10))

  if [[ -f "$INSTALL_LOG" ]]; then
    if grep -q "Installation complete" "$INSTALL_LOG" 2>/dev/null; then
      echo "[OK] Installation complete marker found (${install_elapsed}s)"
      install_ok=true
      break
    fi
    if grep -q "AltOS login:" "$INSTALL_LOG" 2>/dev/null; then
      echo "[OK] Login prompt found during install phase (${install_elapsed}s)"
      install_ok=true
      break
    fi
    if grep -q "Installation failed" "$INSTALL_LOG" 2>/dev/null; then
      echo "[FAIL] Installation failed marker found (${install_elapsed}s)"
      break
    fi
  fi

  if ! kill -0 "$INSTALL_PID" 2>/dev/null; then
    echo "[WARN] QEMU exited early after ${install_elapsed}s"
    break
  fi
done

kill "$INSTALL_PID" 2>/dev/null || true
sleep 2
if kill -0 "$INSTALL_PID" 2>/dev/null; then
  kill -9 "$INSTALL_PID" 2>/dev/null || true
fi
wait "$INSTALL_PID" 2>/dev/null || true

if [[ "$install_ok" != true ]]; then
  echo "[FAIL] Install phase did not complete successfully"
  echo "--- last 50 lines of install log ---"
  tail -50 "$INSTALL_LOG" 2>/dev/null || true
  exit 1
fi

# --- Phase 2: Reboot from disk via UEFI ---
rm -f "$REBOOT_LOG"

echo "[INFO] Phase 2: Reboot from installed disk..."
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -cpu host \
  -drive file="$DISK",format=raw,if=virtio \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$SCRIPT_DIR/ovmf_vars.fd" \
  -serial file:"$REBOOT_LOG" \
  -display none \
  -vga none \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  > "$SCRIPT_DIR/e2e-reboot-nohup.out" 2>&1 &

REBOOT_PID=$!
echo "$REBOOT_PID" > "$SCRIPT_DIR/qemu.pid"
echo "[INFO] Reboot QEMU PID: $REBOOT_PID"

reboot_ok=false
reboot_timeout=300
reboot_elapsed=0
while [[ $reboot_elapsed -lt $reboot_timeout ]]; do
  sleep 10
  reboot_elapsed=$((reboot_elapsed + 10))

  if [[ -f "$REBOOT_LOG" ]]; then
    if grep -q "AltOS login:" "$REBOOT_LOG" 2>/dev/null; then
      echo "[OK] Login prompt found after reboot (${reboot_elapsed}s)"
      reboot_ok=true
      break
    fi
    if grep -q "sddm" "$REBOOT_LOG" 2>/dev/null && grep -q "Reached target Graphical Interface" "$REBOOT_LOG" 2>/dev/null; then
      echo "[OK] Graphical target reached after reboot (${reboot_elapsed}s)"
      reboot_ok=true
      break
    fi
  fi

  if ! kill -0 "$REBOOT_PID" 2>/dev/null; then
    echo "[WARN] Reboot QEMU exited early after ${reboot_elapsed}s"
    break
  fi
done

kill "$REBOOT_PID" 2>/dev/null || true
sleep 2
if kill -0 "$REBOOT_PID" 2>/dev/null; then
  kill -9 "$REBOOT_PID" 2>/dev/null || true
fi
wait "$REBOOT_PID" 2>/dev/null || true

if [[ "$reboot_ok" != true ]]; then
  echo "[FAIL] Reboot phase did not reach login prompt"
  echo "--- last 50 lines of reboot log ---"
  tail -50 "$REBOOT_LOG" 2>/dev/null || true
  exit 1
fi

echo "[SUCCESS] End-to-end VM test passed: install + reboot to login prompt"
exit 0

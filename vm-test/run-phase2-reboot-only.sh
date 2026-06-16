#!/bin/bash
set -uo pipefail

# Phase 2 only: reboot from already-installed disk via UEFI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISK="$SCRIPT_DIR/target-disk.img"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
REBOOT_LOG="$SCRIPT_DIR/reboot-test.log"

cd "$SCRIPT_DIR"

cp "$OVMF_VARS" "$SCRIPT_DIR/ovmf_vars.fd"
rm -f "$REBOOT_LOG" reboot-nohup.out qemu.pid

echo "[INFO] Phase 2: Reboot from installed disk (UEFI)..."
nohup qemu-system-x86_64 \
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
  > reboot-nohup.out 2>&1 &

REBOOT_PID=$!
echo "$REBOOT_PID" > qemu.pid
echo "[INFO] Reboot QEMU PID: $REBOOT_PID"

reboot_ok=false
reboot_timeout=300
reboot_elapsed=0
while [[ $reboot_elapsed -lt $reboot_timeout ]]; do
  sleep 10
  reboot_elapsed=$((reboot_elapsed + 10))

  if [[ -f "$REBOOT_LOG" ]]; then
    if grep -qE " login:" "$REBOOT_LOG" 2>/dev/null; then
      echo "[OK] Login prompt found after reboot (${reboot_elapsed}s)"
      reboot_ok=true
      break
    fi
    if grep -q "Reached target Graphical Interface" "$REBOOT_LOG" 2>/dev/null; then
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
rm -f qemu.pid

if [[ "$reboot_ok" != true ]]; then
  echo "[FAIL] Reboot phase did not reach login prompt"
  echo "--- last 80 lines of reboot log ---"
  tail -80 "$REBOOT_LOG" 2>/dev/null || true
  exit 1
fi

echo "[SUCCESS] Reboot test passed: UEFI boot to login prompt"
exit 0

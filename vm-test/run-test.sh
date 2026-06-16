#!/bin/bash
set -euo pipefail

ISO="/home/jachyyeu/osworld-installer/out/altos-2026.06.12-x86_64.iso"
DISK="/home/jachyyeu/osworld-installer/vm-test/target-disk.img"
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
SERIAL_LOG="/home/jachyyeu/osworld-installer/vm-test/serial.log"

# Copy OVMF vars so we don't corrupt the original
cp "$OVMF_VARS" /home/jachyyeu/osworld-installer/vm-test/ovmf_vars.fd

echo "Starting QEMU test VM..."
echo "ISO:  $ISO"
echo "Disk: $DISK"
echo "Serial log: $SERIAL_LOG"

qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -cpu host \
  -cdrom "$ISO" \
  -drive file="$DISK",format=raw,if=virtio \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file=/home/jachyyeu/osworld-installer/vm-test/ovmf_vars.fd \
  -serial file:"$SERIAL_LOG" \
  -display none \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  &

QEMU_PID=$!
echo "QEMU PID: $QEMU_PID"
echo $QEMU_PID > /home/jachyyeu/osworld-installer/vm-test/qemu.pid

# Tail the serial log with timeout
echo "Monitoring serial output..."
timeout 600 tail -f "$SERIAL_LOG" || true

echo "Test run complete or timed out."
echo "To stop QEMU: kill $(cat /home/jachyyeu/osworld-installer/vm-test/qemu.pid 2>/dev/null || echo 'N/A')"

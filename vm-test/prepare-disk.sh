#!/bin/bash
set -euo pipefail

# Prepare a fresh target disk image for VM testing.
# Creates a 25 GB raw image with a 100 MB FAT32 OSWORLDBOOT partition
# containing install-config.json.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Creating fresh target-disk.img (25 GB)..."
rm -f target-disk.img
dd if=/dev/zero of=target-disk.img bs=1M count=25600 status=progress

sudo bash -c "
  parted -s target-disk.img mklabel gpt
  parted -s target-disk.img mkpart OSWORLDBOOT fat32 1MiB 101MiB
  parted -s target-disk.img set 1 boot on
  rm -rf /tmp/osworld-mnt
  mkdir -p /tmp/osworld-mnt
  LOOP=\$(losetup -f --show target-disk.img)
  partprobe \"\$LOOP\"
  sleep 1
  mkfs.fat -F32 -n OSWORLDBOOT \"\${LOOP}p1\"
  mount \"\${LOOP}p1\" /tmp/osworld-mnt
  cp install-config.json /tmp/osworld-mnt/
  umount /tmp/osworld-mnt
  losetup -d \"\$LOOP\"
  rm -rf /tmp/osworld-mnt
  chown jachyyeu:jachyyeu target-disk.img
"

echo "Done. target-disk.img ready."
ls -la target-disk.img

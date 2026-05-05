#!/bin/bash
set -euo pipefail

# ============================================================
# diagnose.sh — Generate a comprehensive rescue report
# ============================================================

REPORT="/tmp/rescue-report.txt"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}[INFO] Running system diagnostics...${RESET}"

cat > "$REPORT" <<EOF
===============================================
  AltOS Rescue Diagnostic Report
  Generated: $(date)
===============================================

--- DISK / PARTITION LAYOUT ---
$(lsblk -fmo NAME,SIZE,FSTYPE,LABEL,PARTTYPE,MOUNTPOINT)

--- EFI BOOT ENTRIES ---
$(efibootmgr 2>/dev/null || echo "efibootmgr not available")

--- FILESYSTEM HEALTH (btrfs) ---
EOF

# BTRFS health
for part in $(lsblk -rno NAME,FSTYPE | awk '$2=="btrfs" {print "/dev/" $1}'); do
  echo "Partition: $part" >> "$REPORT"
  btrfs device stats "$part" 2>/dev/null >> "$REPORT" || echo "  Could not get stats" >> "$REPORT"
  echo "" >> "$REPORT"
done

cat >> "$REPORT" <<EOF

--- BTRFS SCRUB STATUS ---
$(btrfs scrub status / 2>/dev/null || echo "Root not mounted or not btrfs")

--- LOADED KERNEL MODULES (GPU related) ---
$(lsmod | grep -E "nvidia|amdgpu|i915|radeon" 2>/dev/null || echo "No GPU modules loaded")

--- DMESG (GPU errors) ---
$(dmesg | grep -iE "nvidia|amdgpu|i915|drm|gpu" | tail -n 20 2>/dev/null || echo "No dmesg available")

--- NETWORK STATUS ---
$(ip link show 2>/dev/null || echo "ip command not available")
$(ping -c 1 -W 3 1.1.1.1 2>/dev/null && echo "Internet: REACHABLE" || echo "Internet: UNREACHABLE")

--- X11/WAYLAND LOGS ---
$(ls -la /var/log/Xorg.*.log 2>/dev/null || echo "No Xorg logs found")
$(journalctl -u sddm --no-pager -n 20 2>/dev/null || echo "No sddm journal available")

--- MEMORY ---
$(free -h 2>/dev/null || echo "free not available")

--- CPU INFO ---
$(cat /proc/cpuinfo | grep "model name" | head -n1 2>/dev/null || echo "No CPU info")

--- INSTALLED PACKAGES (relevant) ---
$(pacman -Q | grep -E "nvidia|amdgpu|mesa|linux|grub|refind|sddm|plasma" 2>/dev/null || echo "pacman not available")

--- BOOT LOADER FILES ---
$(ls -la /boot/ 2>/dev/null || echo "/boot not mounted")
$(ls -la /boot/efi/EFI/ 2>/dev/null || echo "EFI partition not mounted")

===============================================
  End of Report
===============================================
EOF

echo -e "${GREEN}[OK] Diagnostic report generated: $REPORT${RESET}"
echo ""
echo -e "${BLUE}[INFO] Report contents:${RESET}"
cat "$REPORT"

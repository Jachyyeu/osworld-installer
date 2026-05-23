#!/bin/bash
set -euo pipefail

# AltOS Installer Physical Test Harness — Phase 3 (First Boot on AltOS)
# Runs once after the first login into the installed AltOS system.

OSWORLD_LABEL="OSWORLDBOOT"
MOUNT_POINT="/mnt/OSWORLDBOOT"
TEST_DIR="$MOUNT_POINT/altos-test"
STATE_FILE="$TEST_DIR/state.json"
LOG_DIR="$TEST_DIR/logs"
SCREENSHOT_DIR="$TEST_DIR/screenshots"

# ─── Helpers ─────────────────────────────────────────────────────────────────
banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    printf "║  %-58s ║\n" "$1"
    echo "╚══════════════════════════════════════════════════════════════╝"
}

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/firstboot.log"
}

die() {
    banner "FATAL: $1"
    write_state "firstboot" "failed" "$1"
    exit 1
}

mount_osworld() {
    if mountpoint -q "$MOUNT_POINT"; then
        return 0
    fi
    mkdir -p "$MOUNT_POINT"
    local dev
    dev="$(lsblk -o NAME,LABEL -nr | awk -v lbl="$OSWORLD_LABEL" '$2==lbl {print "/dev/"$1; exit}')"
    if [[ -z "$dev" ]]; then
        die "OSWORLDBOOT partition not found"
    fi
    mount -t vfat "$dev" "$MOUNT_POINT" || die "Failed to mount OSWORLDBOOT"
}

read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"current_phase":"firstboot","status":"running"}'
    fi
}

write_state() {
    local phase="$1"
    local status="$2"
    local error_msg="${3:-}"
    mkdir -p "$TEST_DIR" "$LOG_DIR" "$SCREENSHOT_DIR"
    local payload
    payload=$(cat <<EOF
{
  "current_phase": "$phase",
  "status": "$status",
  "error": "$error_msg",
  "last_updated": "$(date -Iseconds)"
}
EOF
)
    echo "$payload" > "$STATE_FILE"
    sync
}

take_screenshot() {
    local name="$1"
    local file="$SCREENSHOT_DIR/phase3-$name-$(date +%Y%m%d-%H%M%S).png"
    mkdir -p "$SCREENSHOT_DIR"

    if command -v spectacle &>/dev/null; then
        spectacle -b -o "$file" 2>/dev/null || true
    elif command -v import &>/dev/null; then
        import -window root "$file" 2>/dev/null || true
    elif command -v gnome-screenshot &>/dev/null; then
        gnome-screenshot -f "$file" 2>/dev/null || true
    else
        log "No screenshot tool available (spectacle/import/gnome-screenshot)"
        echo "placeholder" > "$file.txt"
    fi
    log "Screenshot: $file"
}

# ─── Main ────────────────────────────────────────────────────────────────────
banner "PHASE 3: FIRST BOOT ON ALTOS"

mount_osworld
mkdir -p "$TEST_DIR" "$LOG_DIR" "$SCREENSHOT_DIR"

CURRENT_PHASE=$(read_state | python3 -c "import sys,json; print(json.load(sys.stdin).get('current_phase',''))")
if [[ "$CURRENT_PHASE" != "firstboot" ]]; then
    banner "SKIP: current_phase is '$CURRENT_PHASE', expected 'firstboot'"
    exit 0
fi

write_state "firstboot" "running" ""
log "First-boot test harness starting"

# Prevent the onboarding wizard from showing (mark as seen)
mkdir -p /home/testuser/.config/altos
touch /home/testuser/.config/altos/post-install-seen
touch /home/testuser/.config/altos/first-boot-done

# Wait for desktop (KDE Plasma)
log "Waiting for Plasma desktop..."
for i in {1..60}; do
    if pgrep -x plasmashell >/dev/null 2>&1; then
        log "Plasma desktop detected"
        break
    fi
    sleep 2
done

sleep 5
take_screenshot "desktop"

# Check if wizard is running and wait
if pgrep -f wizard_gui.py >/dev/null 2>&1; then
    log "First-boot wizard detected; waiting for it..."
    for i in {1..30}; do
        take_screenshot "wizard-step-$i"
        if ! pgrep -f wizard_gui.py >/dev/null 2>&1; then
            log "Wizard closed"
            break
        fi
        sleep 5
    done
fi

# Open terminal and collect diagnostics
log "Collecting system diagnostics..."

if command -v konsole &>/dev/null; then
    konsole --new-tab -e bash -c "neofetch > $LOG_DIR/neofetch.log 2>&1; echo 'neofetch done'; sleep 2" &
elif command -v gnome-terminal &>/dev/null; then
    gnome-terminal -- bash -c "neofetch > $LOG_DIR/neofetch.log 2>&1; echo 'neofetch done'; sleep 2" &
else
    log "No known terminal emulator found; running neofetch directly"
    neofetch > "$LOG_DIR/neofetch.log" 2>&1 || true
fi

sleep 3
lspci | grep -i vga > "$LOG_DIR/gpu.log" 2>&1 || true

# Test WiFi
if command -v nmcli &>/dev/null; then
    nmcli dev wifi list > "$LOG_DIR/wifi.log" 2>&1 || true
    log "WiFi scan saved"
else
    log "nmcli not found; skipping WiFi test"
fi

# Screenshot after diagnostics
take_screenshot "diagnostics"

# Configure rEFInd to boot Windows next
if [[ -f /boot/efi/EFI/refind/refind.conf ]]; then
    log "Setting rEFInd default_selection to Windows"
    if grep -q "default_selection" /boot/efi/EFI/refind/refind.conf; then
        sed -i 's/^default_selection.*/default_selection "Windows"/' /boot/efi/EFI/refind/refind.conf
    else
        echo 'default_selection "Windows"' >> /boot/efi/EFI/refind/refind.conf
    fi
else
    log "WARNING: /boot/efi/EFI/refind/refind.conf not found"
fi

# Update state
write_state "verify" "running" ""
log "Phase 3 complete. Rebooting to Windows for verification..."

sleep 3
reboot

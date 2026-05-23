#!/bin/bash
set -euo pipefail

# AltOS Installer Physical Test Harness — Phase 2 (Arch Live)
# Run inside the Arch Live environment after booting from rEFInd.

OSWORLD_LABEL="OSWORLDBOOT"
MOUNT_POINT="/mnt/OSWORLDBOOT"
TEST_DIR="$MOUNT_POINT/altos-test"
STATE_FILE="$TEST_DIR/state.json"
LOG_DIR="$TEST_DIR/logs"

# ─── Helpers ─────────────────────────────────────────────────────────────────
banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    printf "║  %-58s ║\n" "$1"
    echo "╚══════════════════════════════════════════════════════════════╝"
}

die() {
    banner "FATAL: $1"
    write_state "live" "failed" "$1"
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
        echo '{"current_phase":"live","status":"running"}'
    fi
}

write_state() {
    local phase="$1"
    local status="$2"
    local error_msg="${3:-}"
    mkdir -p "$TEST_DIR" "$LOG_DIR"
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

# ─── Main ────────────────────────────────────────────────────────────────────
banner "PHASE 2: ARCH LIVE INSTALL"

mount_osworld
mkdir -p "$TEST_DIR" "$LOG_DIR"

CURRENT_PHASE=$(read_state | python3 -c "import sys,json; print(json.load(sys.stdin).get('current_phase',''))")
if [[ "$CURRENT_PHASE" != "live" ]]; then
    banner "SKIP: current_phase is '$CURRENT_PHASE', expected 'live'"
    exit 0
fi

write_state "live" "running" ""

# Locate the installer
INSTALLER=""
for cand in \
    "$MOUNT_POINT/install.sh" \
    "/opt/altos/install.sh" \
    "$(find / -maxdepth 4 -name 'install.sh' -path '*/scripts/installer/*' 2>/dev/null | head -1)";
do
    [[ -f "$cand" ]] && INSTALLER="$cand" && break
done

if [[ -z "$INSTALLER" ]]; then
    die "Could not locate install.sh"
fi

banner "Running installer: $INSTALLER"
chmod +x "$INSTALLER"

# Run installer and capture everything
if bash "$INSTALLER" --confirm > >(tee "$LOG_DIR/install.log") 2>&1; then
    banner "Installation completed successfully"
    write_state "firstboot" "running" ""

    # Copy the first-boot test script onto the installed system if path is known
    FIRSTBOOT_SRC="${BASH_SOURCE[0]%/*}/altos-test-firstboot.sh"
    if [[ -f "$FIRSTBOOT_SRC" ]]; then
        # Try to find the new root
        ALTOS_ROOT=""
        for mp in /mnt/altos /mnt/root /mnt/arch; do
            [[ -d "$mp/etc" ]] && ALTOS_ROOT="$mp" && break
        done
        if [[ -n "$ALTOS_ROOT" ]]; then
            cp "$FIRSTBOOT_SRC" "$ALTOS_ROOT/usr/local/bin/altos-test-firstboot.sh"
            chmod +x "$ALTOS_ROOT/usr/local/bin/altos-test-firstboot.sh"
            # Install systemd service
            cat > "$ALTOS_ROOT/etc/systemd/system/altos-test-firstboot.service" <<'EOF'
[Unit]
Description=AltOS Physical Test Harness — First Boot
After=graphical.target network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/altos-test-firstboot.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF
            mkdir -p "$ALTOS_ROOT/etc/systemd/system/graphical.target.wants"
            ln -sf /etc/systemd/system/altos-test-firstboot.service \
                "$ALTOS_ROOT/etc/systemd/system/graphical.target.wants/altos-test-firstboot.service"
            banner "Installed first-boot test service"
        fi
    fi

    banner "PHASE 2 COMPLETE — Rebooting into AltOS"
    sleep 3
    reboot
else
    EXIT_CODE=$?
    ERROR_MSG="Installer exited with code $EXIT_CODE. See $LOG_DIR/install.log"
    die "$ERROR_MSG"
fi

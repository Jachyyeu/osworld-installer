# Installer Scripts

> **Important:** These scripts run **inside an Arch Linux Live ISO**, not on Windows.
> Boot your PC from the Arch Live USB, then run these scripts to install Linux.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    WINDOWS SIDE (Tauri GUI)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Welcome      │→│ System Check │→│ Disk Selection   │  │
│  │ (dual/replace)│  │ (UEFI/Secure)│  │ (shrink/slider)  │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│           ↓                                                    │
│  ┌──────────────┐  ┌──────────────────────────────────────┐  │
│  │ User Setup   │→│ Installation Progress                │  │
│  │ (name/pwd)   │  │ • Shrink C:                          │  │
│  └──────────────┘  │ • Create OSWORLDBOOT (2GB FAT32)     │  │
│                    │ • Create raw Linux partition         │  │
│                    │ • Download Arch ISO                  │  │
│                    │ • Install rEFInd → reboot            │  │
│                    └──────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              ARCH LIVE ISO (scripts/installer/)              │
│  live-bridge.sh ──→ install.sh ──→ lib/*.sh                 │
│       ↓                ↓              ↓                      │
│  Mount OSWORLDBOOT  Parse config   disk / bootstrap / etc.   │
│  Read config.json   Partition      First-boot wizard setup   │
│  Unmount            Install AltOS                            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              FIRST BOOT (scripts/first-boot/)                │
│  wizard.sh ──→ steps/                                        │
│    • import-windows.sh   (dualboot only)                     │
│    • pick-theme.sh       (KDE presets)                       │
│    • setup-apps.sh       (Steam, Discord, etc.)              │
│    • finalize.sh         (flag + reboot offer)               │
└─────────────────────────────────────────────────────────────┘
```

## How it works

1. **Tauri GUI (Windows side)** collects your preferences:
   - Disk to use
   - Installation mode (wipe or dual-boot with Windows)
   - User name, password, timezone, etc.

2. The GUI writes a JSON file to `/tmp/install-config.json`.

3. **These bash scripts** read that JSON and perform the actual installation.

## Files

| File | Purpose |
|------|---------|
| `install.sh` | Main orchestrator. Run this. |
| `live-bridge.sh` | Auto-finds staged config from OSWORLDBOOT partition and runs `install.sh` |
| `lib/disk.sh` | Partitioning (shrink Windows, create root/home, reuse Windows EFI in dualboot) |
| `lib/bootstrap.sh` | Format partitions, mount, `pacstrap` base system |
| `lib/drivers.sh` | Auto-detect GPU/WiFi and install correct drivers |
| `lib/system.sh` | Timezone, locale, hostname, user, sudo, NetworkManager |
| `lib/migration.sh` | Migrate Documents, Pictures, bookmarks, WiFi from Windows |
| `lib/bootloader.sh` | Install GRUB with Windows detection (`os-prober`) |
| `lib/logging.sh` | Universal logging to both Live env and target system |
| `lib/compatibility.sh` | Hardware compatibility check before partitioning |
| `example-config.json` | Example input for testing |

### New Modules

#### `scripts/first-boot/`

Post-installation wizard that runs on the user's first login:

- **`wizard.sh`** — Main orchestrator. Checks `~/.config/altos/first-boot-done`, runs steps in order.
- **`steps/import-windows.sh`** — Detects Windows partition, offers checkbox-style import of Documents, Pictures, Bookmarks, WiFi profiles.
- **`steps/pick-theme.sh`** — Interactive theme picker: Windows 11 style (default), Clean Linux, or Dark mode. Applies KDE configs from `/usr/share/altos/themes/`.
- **`steps/setup-apps.sh`** — Optional installs for Steam, Discord, Spotify, VS Code via pacman/flatpak.
- **`steps/finalize.sh`** — Creates completion flag, offers reboot.

#### `scripts/uninstaller/`

Rescue tools to remove AltOS and restore Windows:

- **`uninstall.sh`** — Linux-side script. Detects AltOS partitions, removes them, cleans EFI entries, restores Windows Boot Manager via `efibootmgr`, optionally expands Windows partition. Requires typed confirmation `REMOVE`.
- **`windows-uninstall.ps1`** — Windows-side PowerShell script. Deletes Linux partitions via `diskpart`, removes GRUB/rEFInd from EFI, restores Windows Boot Manager via `bcdedit`, optionally expands C: drive. Requires typed confirmation `REMOVE`.

#### `packages/basic.yaml`

Defines the free AltOS Basic package:
- Base packages: KDE Plasma desktop, Firefox, LibreOffice, utilities
- Post-install scripts: Windows 11 theme, shortcut mappings, Firefox privacy config, Dolphin places, LibreOffice defaults
- Services: sddm, NetworkManager, bluetooth
- First-boot wizard enabled

## Execution Order

`install.sh` runs the following steps in order:

1. **`verify_environment`** — Check root, UEFI, internet
2. **`verify_compatibility`** — Detect GPU, WiFi, storage, audio. Blocks on eMMC.
3. **`partition_disk`** — Partition the target disk (wipe or shrink Windows)
4. **`get_partitions`** — Detect EFI (reuse Windows ESP in dualboot), root, home
5. **`format_and_mount_partitions`** — Format root+home; do NOT format existing EFI in dualboot
6. **`bootstrap_system`** — `pacstrap` Arch base system
7. **`install_drivers`** — Detect and install GPU + WiFi drivers, regenerate initramfs
8. **`configure_system`** — Timezone, locale, hostname, user, sudo, NetworkManager
9. **`migrate_windows_files`** — (dual-boot only) Copy user files, bookmarks, WiFi profiles
10. **`install_bootloader`** — GRUB + os-prober for Windows detection
11. **`enable_first_boot_wizard`** — Copy wizard to target, create KDE autostart entry
12. **`finalize`** — Unmount, sync, copy log to user home

## Boot Staging Flow (Windows → Arch Live ISO)

This is the full handoff from the Windows app to the Linux installer:

1. **Windows app** stages the installation:
   - Shrinks the C: drive
   - Creates a 2 GB FAT32 partition labeled **OSWORLDBOOT**
   - Creates a second raw partition for Linux
   - Downloads the Arch Linux ISO to `OSWORLDBOOT:\arch.iso`
   - Writes `install-config.json` to the `OSWORLDBOOT` partition
   - Installs **rEFInd** bootloader to the EFI System Partition
   - Adds a menu entry that boots the Arch ISO from `OSWORLDBOOT`

2. **User reboots** and selects *"OSWorld Installer"* from the rEFInd menu.

3. **Arch Live ISO boots** (loaded from the staged ISO on `OSWORLDBOOT`).

4. **Inside the Live ISO**, run:
   ```bash
   sudo bash /path/to/live-bridge.sh --confirm
   ```

5. **`live-bridge.sh`** does the bridge work:
   - Mounts the `OSWORLDBOOT` partition
   - Copies `install-config.json` to `/tmp/install-config.json`
   - Validates the JSON
   - Unmounts the partition
   - Hands off to `install.sh` with the same arguments (`--dry-run` or `--confirm`)

6. **`install.sh`** reads the config and installs Arch Linux.

## Disk Behavior

### Wipe Mode
- Creates **new** EFI System Partition (512 MB)
- Creates Linux Root (20 GB) and Linux Home (remainder)

### Dual-Boot Mode
- **Reuses existing Windows EFI partition** (does NOT create a second one)
- Shrinks Windows NTFS partition by ~20 GB
- Creates Linux Root (20 GB) and Linux Home (remainder)
- Safety check: aborts if more than one EFI partition is detected

## Uninstall Instructions

### From Windows (if you can still boot)
1. Open PowerShell as Administrator.
2. Run: `powershell -ExecutionPolicy Bypass -File scripts/uninstaller/windows-uninstall.ps1`
3. Type `REMOVE` when prompted.
4. Reboot.

### From Linux Live USB (if Windows won't boot)
1. Boot any Linux Live USB.
2. Open a terminal.
3. Run: `sudo bash scripts/uninstaller/uninstall.sh`
4. Type `REMOVE` when prompted.
5. Optional: expand Windows partition to reclaim space.
6. Reboot.

## Usage

### Manual run (with mock config)
```bash
# Show what would happen without changing anything (default)
sudo bash scripts/installer/install.sh --dry-run

# Actually install
sudo bash scripts/installer/install.sh --confirm
```

### Automatic bridge (from staged Windows setup)
```bash
# Inside Arch Live ISO — auto-detect staged config and install
sudo bash scripts/installer/live-bridge.sh --confirm
```

## Testing Checklist

- [ ] `--dry-run` prints plan but touches nothing
- [ ] `--confirm` required for destructive operations
- [ ] `lib/disk.sh` — dualboot finds existing EFI, does not format it
- [ ] `lib/disk.sh` — dualboot aborts if >1 EFI partition detected
- [ ] `lib/disk.sh` — wipe mode creates new EFI, root, home
- [ ] `lib/bootstrap.sh` — formats only partitions created in current session
- [ ] `lib/bootloader.sh` — GRUB detects Windows via os-prober
- [ ] `first-boot/wizard.sh` — runs only if `~/.config/altos/first-boot-done` is absent
- [ ] `first-boot/steps/import-windows.sh` — skips gracefully if no Windows partition found
- [ ] `uninstaller/uninstall.sh` — requires `REMOVE` typed confirmation
- [ ] `uninstaller/uninstall.sh` — restores Windows Boot Manager via efibootmgr
- [ ] `uninstaller/windows-uninstall.ps1` — removes BCD entries for OSWorld Installer

## Safety

- `--dry-run` prints every step but touches **nothing**.
- `--confirm` is required to make real changes.
- `live-bridge.sh` refuses to run if the `OSWORLDBOOT` partition or config is missing.
- The script refuses to run if the target disk is mounted (protects the Live USB).
- `set -euo pipefail` ensures any error stops the script immediately.
- `lib/compatibility.sh` blocks installation on unsupported hardware (eMMC).
- On any failure, `/tmp/altos-crash-report.txt` contains the full log.
- Destructive actions in Rust backend require typed confirmation `"OSWORLD"`.
- `cleanup_staging()` removes Linux partitions and expands C: drive, but requires `"OSWORLD"` confirmation.

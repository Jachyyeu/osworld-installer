# AltOS Installer — Physical Hardware Test Harness

A cross-reboot state-machine test suite that validates the **full** AltOS Installer product on a dedicated Lenovo test PC: real disk partitioning, real rEFInd installation, real Secure Boot handling, real first-boot wizard, and real Windows/AltOS dual-boot switching.

## Architecture

```
[Windows] ──Phase 1──► [Arch Live] ──Phase 2──► [AltOS First Boot] ──Phase 3──► [Windows Verify] ──Phase 4──► Report
   │                        │                          │                        │
   └─ altos-test-harness.ps1  altos-test-live.sh        altos-test-firstboot.sh   altos-test-verify.ps1
```

State is persisted across reboots via the **OSWORLDBOOT** partition (FAT32), which is readable from both Windows and Linux:

```
OSWORLDBOOT:\altos-test\
  state.json          ← current phase, status, retry count
  screenshots\        ← phase screenshots (PNG)
  logs\               ← install.log, neofetch.log, wifi.log, gpu.log
  test-report.json    ← final aggregated report
```

## Prerequisites

### Hardware
- Lenovo test PC (any modern UEFI laptop/desktop)
- Windows 11 installed
- At least 60 GB free space on C: drive
- Internet access

### Software (on Windows)
- PowerShell 5.1+ (run as **Administrator**)
- Git
- Node.js 20+
- Rust toolchain
- Tauri CLI (`cargo install tauri-cli`)
- UIAutomationClient (built into Windows)

### Optional (for screenshots on Linux)
- `spectacle` (KDE) or `imagemagick` (import) or `gnome-screenshot`

## Setup

1. **Clone the repo** on the Lenovo PC:
   ```powershell
   git clone https://github.com/Jachyyeu/osworld-installer.git C:\osworld-installer
   cd C:\osworld-installer
   ```

2. **Create the safety marker file** (prevents accidental runs on the wrong PC):
   ```powershell
   New-Item -ItemType File -Path C:\.altos-test-lenovo -Force
   ```

3. **Build the installer** (or let Phase 1 build it automatically):
   ```powershell
   npm install
   npm run tauri build
   ```

## Running the Harness

### Dry Run (recommended first time)
Simulates all UI interactions, state transitions, and screenshots **without** clicking anything, modifying disks, or rebooting.

```powershell
Set-Location C:\osworld-installer
.\tools\physical-test\altos-test-harness.ps1 -DryRun
```

This validates:
- Paths and binaries exist
- UI Automation can locate Tauri window elements
- Screenshot pipeline works
- State JSON read/write works

### Full Test

```powershell
Set-Location C:\osworld-installer
.\tools\physical-test\altos-test-harness.ps1
```

You will be prompted to:
1. Confirm this is the test PC
2. Create a Windows System Restore Point
3. Confirm before the final reboot into Arch Live

### Phase-by-phase (manual intervention)

If a phase fails or you need to resume:

| Phase | Script | When to run |
|-------|--------|-------------|
| **1 — Windows Installer** | `altos-test-harness.ps1` | In Windows PowerShell (Admin) |
| **2 — Arch Live Install** | `altos-test-live.sh` | After rEFInd boots into Arch Live desktop |
| **3 — AltOS First Boot** | `altos-test-firstboot.sh` | Auto-runs via systemd on first AltOS login |
| **4 — Windows Verify** | `altos-test-verify.ps1` | After rebooting back to Windows from AltOS |

### Running a single phase manually

Read the current state first:

```powershell
$vol = Get-Volume | Where-Object FileSystemLabel -eq "OSWORLDBOOT"
Get-Content "$($vol.DriveLetter):\altos-test\state.json" | ConvertFrom-Json
```

Edit `state.json` to set `current_phase` to the phase you want to run, then execute that phase's script.

## Cleanup / Uninstall

Remove AltOS and all test artifacts:

```powershell
.\tools\physical-test\altos-test-harness.ps1 -Cleanup
```

Or run the dedicated Windows uninstaller script:

```powershell
.\scripts\uninstaller\windows-uninstall.ps1
```

## Safety Features

- **PC marker file**: `C:\.altos-test-lenovo` must exist, or you must type a confirmation string.
- **System Restore Point**: Created automatically before Phase 1 (unless skipped).
- **State machine**: Resumes gracefully if a reboot or failure interrupts the flow.
- **No silent disk changes**: The installer itself requires typed confirmation (`OSWORLD`) for partitioning; the harness only automates the Tauri UI up to that point.

## Output Artifacts

After a complete run, `OSWORLDBOOT:\altos-test\test-report.json` contains:

```json
{
  "overall": "pass",
  "phases": {
    "windows": "pass",
    "live": "pass",
    "firstboot": "pass",
    "verify": "pass"
  },
  "duration_seconds": 1847,
  "screenshots": [...],
  "logs": [...],
  "lenovo_specs": {
    "c_drive_gb": 512
  }
}
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| UI Automation can't find button | The harness falls back to coordinate-based clicks. If those are wrong for your screen resolution, edit the `Click-AtCoordinates` calls in `altos-test-harness.ps1`. |
| OSWORLDBOOT not found | Phase 1 creates it during staging. Before Phase 1, state falls back to `C:\altos-test`. |
| First-boot script didn't run | Check `systemctl status altos-test-firstboot.service` on AltOS. |
| Live script can't find installer | Ensure `install.sh` is on the OSWORLDBOOT partition or in `/opt/altos/`. |

## License

Same as the OSWorld Installer project.

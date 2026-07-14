# Agent Guide — AltOS Installer

## Project Overview

This is a **Tauri v2 + React/TypeScript** application that installs a custom Fedora KDE Spin distribution ("AltOS") onto a Windows PC. The flow is:

1. **Windows app** (this repo) stages files onto a spare partition
2. **Fedora KDE Spin Live ISO** boots and auto-runs the installer
3. **First-boot wizard** runs after reboot into the new system

## Build Commands

### Frontend
```bash
npm install
npm run dev      # development server
npm run build    # production build
```

### Rust Backend
```bash
cd src-tauri
cargo check
cargo test
cargo build      # debug build
cargo build --release
```

### Full Tauri App (Windows)
```bash
npm run tauri build
```

### Fedora KDE Spin ISO (Phase 1)
In Phase 1, the installer uses the official Fedora 42 KDE Spin ISO. Download it using:
```bash
curl -L -o ./out/Fedora-KDE-Desktop-Live-42-1.1.x86_64.iso \
  https://download.fedoraproject.org/pub/fedora/linux/releases/42/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-42-1.1.x86_64.iso
```
The expected SHA256 checksum is `cf4beecc21ffae86d0e368797cbcc02ba7f4c6549c626db01b1d3f4e1444da85`.

## Project Structure

| Path | Purpose |
|------|---------|
| `src/` | React frontend (TypeScript + Tailwind) |
| `src-tauri/src/main.rs` | Rust backend (Windows-only platform logic) |
| `src-tauri/tauri.conf.json` | Tauri configuration |
| `scripts/installer/` | Bash installer engine (runs inside Fedora Live ISO) |
| `scripts/first-boot/` | Post-install wizard (runs on first boot of installed system) |
| `scripts/recovery/` | Recovery and rescue scripts |
| `packages/basic.yaml` | AltOS Basic package definition and post-install scripts |
| `auto-test.ps1` | PowerShell end-to-end test runner (Windows target PC) |

## Key Conventions

- **ISO paths are hardcoded** to reference Fedora's signed shim/kernel path structure (`/images/pxeboot/...` and `/LiveOS/...`) in the staging scripts.
- **Installer scripts must be bash** and work inside the Fedora Live environment.
- **Python is available** in the live ISO by default.
- **Test mode** (`VITE_TEST_MODE=true`) gates dangerous operations and enables auto-test integration.
- **Dry-run mode** (`--dry-run`) in `install.sh` simulates all steps without touching disks.

## Release Process

1. Update version in `src-tauri/tauri.conf.json`
2. Build and test the Windows installer on a real PC
3. Tag and push: `git tag v0.x.y && git push origin v0.x.y`
4. The GitHub Actions release workflow will build the Windows `.exe`, download/verify the Fedora KDE ISO, and attach them to a draft release.
5. Update staging scripts or `USE_CUSTOM_ISO` variables to point to the correct release/mirror URLs.

## Testing

- **Unit tests:** `cd src-tauri && cargo test`
- **Frontend type check:** `npx tsc --noEmit`
- **Shell script lint:** `find scripts/ -name '*.sh' | xargs shellcheck -S warning`
- **End-to-end:** Run `auto-test.ps1` on the Windows test target (`jachym-pc`)

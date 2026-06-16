# Agent Guide — AltOS Installer

## Project Overview

This is a **Tauri v2 + React/TypeScript** application that installs a custom Arch Linux distribution ("AltOS") onto a Windows PC. The flow is:

1. **Windows app** (this repo) stages files onto a spare partition
2. **Custom Arch ISO** boots and auto-runs the installer
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

### Custom Arch ISO (Linux, requires sudo)
```bash
sudo mkarchiso -v -w /tmp/archiso-tmp -o ./out archiso-profile/
```

The output will be at `./out/altos-YYYY.MM.DD-x86_64.iso`.

## Project Structure

| Path | Purpose |
|------|---------|
| `src/` | React frontend (TypeScript + Tailwind) |
| `src-tauri/src/main.rs` | Rust backend (Windows-only platform logic) |
| `src-tauri/tauri.conf.json` | Tauri configuration |
| `scripts/installer/` | Bash installer engine (runs inside Arch Live ISO) |
| `scripts/first-boot/` | Post-install wizard (runs on first boot of installed system) |
| `scripts/recovery/` | Recovery and rescue scripts |
| `packages/basic.yaml` | AltOS Basic package definition and post-install scripts |
| `archiso-profile/` | Custom archiso profile (releng + our scripts) |
| `auto-test.ps1` | PowerShell end-to-end test runner (Windows target PC) |

## Key Conventions

- **ISO paths are hardcoded** as `/arch/boot/x86_64/...` in both the Windows backend and the ISO profile. Do not change `install_dir` in `profiledef.sh` without updating the Windows code.
- **Installer scripts must be bash** and work inside the Arch Live environment.
- **Python is available** in the live ISO (explicitly added to `packages.x86_64`).
- **Test mode** (`VITE_TEST_MODE=true`) gates dangerous operations and enables auto-test integration.
- **Dry-run mode** (`--dry-run`) in `install.sh` simulates all steps without touching disks.

## Release Process

1. Update version in `src-tauri/tauri.conf.json`
2. Build and test the Windows installer on a real PC
3. Build the custom ISO: `sudo mkarchiso -v -w /tmp/archiso-tmp -o ./out archiso-profile/`
4. Tag and push: `git tag v0.x.y && git push origin v0.x.y`
5. The GitHub Actions release workflow will build the Windows `.exe` and attach it to a draft release
6. Manually upload the `.iso` to the same release
7. Update `USE_CUSTOM_ISO` in `src-tauri/src/main.rs` to point to the release URL

## Testing

- **Unit tests:** `cd src-tauri && cargo test`
- **Frontend type check:** `npx tsc --noEmit`
- **Shell script lint:** `find scripts/ -name '*.sh' | xargs shellcheck -S warning`
- **End-to-end:** Run `auto-test.ps1` on the Windows test target (`jachym-pc`)

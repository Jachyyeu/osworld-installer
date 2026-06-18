# AltOS Installer — Project Status

**Saved:** 2026-06-16  
**State:** In progress — all four product phases architected; Windows installer v0.2.6 building, real-hardware test pending.

## What Was Completed This Session

1. **Phase 1 — Unattended boot fix**
   - rEFInd now defaults to `OSWorld Installer` and ignores NVRAM last-boot
   - Windows installer uses `bcdedit /bootsequence` for one-time next boot
   - Tagged `v0.1.1` and triggered GitHub Actions release build; later fixed CI failures and tagged `v0.2.6`

2. **Phase 2 — Edition system**
   - Added `packages/home.yaml`, `gaming.yaml`, `creative.yaml`, `privacy.yaml`
   - Installer reads edition from `install-config.json` and applies the right package set
   - Edition selection UI wired through to Rust backend

3. **Phase 3 — Per-app customization**
   - Browser picker (Brave / Chromium / Firefox)
   - Email client picker (Thunderbird / Evolution / Geary)
   - Music player picker (Strawberry / Rhythmbox / VLC)
   - LibreOffice with Windows-style skins toggle
   - Customization saved to `install-config.json` and applied during pacstrap

4. **Phase 4 — App store + monetization**
   - Added AltOS App Store (PyQt6) with curated pacman/flatpak catalog
   - App Store copied to target system and added to apps menu
   - Added Stripe payment-link flow for paid editions
   - Added `verify_edition_payment` backend hook for future license-server integration

5. **Automated testing**
   - Created `vm-test/spam-e2e.sh` to build ISO and run back-to-back end-to-end tests
   - Supports `--loop N` and `--editions home,gaming,creative,privacy`

6. **Release infrastructure**
   - Bumped version to `0.2.1`
   - Updated release workflow to attach ISO automatically and include code-signing placeholders
   - Added `CODESIGN.md` with Azure Trusted Signing and certificate instructions

## Current Blocker

Real-hardware test on `jachym-pc` is still pending. The PC is currently running the existing Arch install and is offline on Tailscale.

## Next Steps

1. Build `v0.2.6` ISO and Windows installer (GitHub Actions after tagging `v0.2.6`).
2. On `jachym-pc`:
   - Reboot to Windows
   - Run the new `AltOS-Installer.exe`
   - Select an edition and continue
   - The installer should reboot automatically into the AltOS installer
3. Verify the install completes and the first-boot wizard / App Store work.
4. Replace the Stripe placeholder links in `src-tauri/src/main.rs` with real payment links.
5. Set up code signing secrets when ready.

## Quick Commands

```bash
# Tag and build v0.2.6 release
git tag v0.2.6
git push origin v0.2.6

# Run automated VM test loop
cd vm-test
./spam-e2e.sh --editions home,gaming,creative,privacy
```

## Notes

- Tailscale target IP: `100.103.228.71` (target must run `tailscale login` after install)
- Windows test PC user/pass: `JA` / `Klokan2009`

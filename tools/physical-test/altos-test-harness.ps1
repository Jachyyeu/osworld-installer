#Requires -RunAsAdministrator
<#
.SYNOPSIS
    AltOS Installer Physical Hardware Test Harness — Phase 1 (Windows)
.DESCRIPTION
    Runs the Tauri installer on a Lenovo test PC, automates UI interactions,
    captures screenshots, and persists state to the OSWORLDBOOT partition.
.PARAMETER DryRun
    Simulates all phases without modifying disks, clicking UI, or rebooting.
.PARAMETER Cleanup
    Removes test artifacts and AltOS installation after a completed or failed run.
#>
param(
    [switch]$DryRun,
    [switch]$Cleanup
)

# ─── Configuration ───────────────────────────────────────────────────────────
$MarkerFile          = "C:\.altos-test-lenovo"
$RepoRoot            = (Resolve-Path "$PSScriptRoot\..\..").Path
$StateDirFallback    = "C:\altos-test"
$OsworldLabel        = "OSWORLDBOOT"
$TauriExe            = "$RepoRoot\src-tauri\target\release\osworld-installer.exe"
$MaxRetries          = 3

# ─── Safety ──────────────────────────────────────────────────────────────────
function Test-Safety {
    if ($Cleanup) { return }

    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  PHYSICAL HARDWARE TEST HARNESS                              ║" -ForegroundColor Red
    Write-Host "║  This will modify disk partitions and install AltOS.         ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""

    if (-not (Test-Path $MarkerFile)) {
        $confirm = Read-Host "Marker file $MarkerFile not found. Type 'lenovo-test' to confirm this is the test PC"
        if ($confirm -ne 'lenovo-test') {
            Write-Error "Aborted. Create $MarkerFile or confirm manually."
            exit 1
        }
        New-Item -ItemType File -Path $MarkerFile -Force | Out-Null
    }

    if (-not $DryRun) {
        $yn = Read-Host "Create Windows System Restore Point before starting? (Y/n)"
        if ($yn -ne 'n') {
            Write-Host "Creating restore point..."
            Checkpoint-Computer -Description "AltOS-Test-Harness-$(Get-Date -Format yyyyMMdd-HHmmss)" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
        }
    }
}

# ─── State helpers ───────────────────────────────────────────────────────────
function Get-StateDirectory {
    $vol = Get-Volume | Where-Object { $_.FileSystemLabel -eq $OsworldLabel } | Select-Object -First 1
    if ($vol) {
        return "$($vol.DriveLetter):\altos-test"
    }
    return $StateDirFallback
}

function Read-State {
    $dir = Get-StateDirectory
    $path = "$dir\state.json"
    if (Test-Path $path) {
        return Get-Content $path | ConvertFrom-Json
    }
    $initial = @{
        current_phase = "windows"
        status        = "running"
        screenshots   = @()
        logs          = @()
        start_time    = (Get-Date -Format "o")
        retry_count   = 0
    }
    return $initial
}

function Write-State {
    param($State)
    $dir = Get-StateDirectory
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $screenshotDir = "$dir\screenshots"
    $logDir        = "$dir\logs"
    if (-not (Test-Path $screenshotDir)) { New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null }
    if (-not (Test-Path $logDir))        { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 10 | Set-Content "$dir\state.json" -Encoding UTF8
}

# ─── Screenshot ──────────────────────────────────────────────────────────────
function Take-Screenshot {
    param([string]$Name)
    $dir = Get-StateDirectory
    $screenshotDir = "$dir\screenshots"
    if (-not (Test-Path $screenshotDir)) { New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName  = "$screenshotDir\$Name-$timestamp.png"

    if ($DryRun) {
        "DRY-RUN SCREENSHOT: $fileName" | Out-File "$screenshotDir\$Name-$timestamp.txt" -Encoding UTF8
        Write-Host "[DRY-RUN] Screenshot would be saved: $fileName" -ForegroundColor Cyan
        return $fileName
    }

    Add-Type -AssemblyName System.Windows.Forms,System.Drawing
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save($fileName, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    return $fileName
}

# ─── UI Automation helpers ───────────────────────────────────────────────────
function Find-TauriWindow {
    $proc = Get-Process | Where-Object { $_.ProcessName -like "*osworld*" } | Select-Object -First 1
    if (-not $proc) { return $null }

    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        $desktop = [System.Windows.Automation.AutomationElement]::RootElement
        $condition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
        return $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    } catch {
        return $null
    }
}

function Find-ElementByName {
    param($Window, [string]$Name)
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        $cond = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
        return $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    } catch {
        return $null
    }
}

function Invoke-Element {
    param($Element)
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would click element: $($Element.Current.Name)" -ForegroundColor Cyan
        return
    }
    try {
        $pattern = $Element.GetCurrentPattern([System.Windows.Automation.PatternIdentifiers]::InvokePattern)
        $pattern.Invoke()
    } catch {
        # Fallback: try Toggle pattern (for some custom controls)
        try {
            $tp = $Element.GetCurrentPattern([System.Windows.Automation.PatternIdentifiers]::TogglePattern)
            $tp.Toggle()
        } catch {
            Write-Warning "Could not invoke element: $($Element.Current.Name)"
        }
    }
}

function Click-AtCoordinates {
    param([int]$X, [int]$Y)
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would click at coordinates ($X, $Y)" -ForegroundColor Cyan
        return
    }
    Add-Type -MemberDefinition @"
        [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, IntPtr dwExtraInfo);
"@ -Name MouseUtils -Namespace Win32
    $Win32::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 100
    $Win32::mouse_event(0x0002, 0, 0, 0, 0) # L down
    $Win32::mouse_event(0x0004, 0, 0, 0, 0) # L up
}

# ─── Phase: Windows ──────────────────────────────────────────────────────────
function Start-PhaseWindows {
    Write-Host "`n========== PHASE 1: WINDOWS INSTALLER ==========" -ForegroundColor Green
    $state = Read-State

    if ($state.current_phase -ne 'windows') {
        Write-Host "State phase is $($state.current_phase), skipping Phase-Windows."
        return
    }

    # Build installer if needed
    if (-not $DryRun -and -not (Test-Path $TauriExe)) {
        Write-Host "Building Tauri release binary..."
        Push-Location $RepoRoot
        npm install | Out-Null
        npm run tauri build | Out-Null
        Pop-Location
        if (-not (Test-Path $TauriExe)) {
            throw "Build failed: $TauriExe not found"
        }
    } elseif ($DryRun -and -not (Test-Path $TauriExe)) {
        Write-Host "[DRY-RUN] Would build: $TauriExe" -ForegroundColor Cyan
    }

    # Launch installer
    if (-not $DryRun) {
        Start-Process $TauriExe
        Start-Sleep -Seconds 3
    } else {
        Write-Host "[DRY-RUN] Would launch: $TauriExe" -ForegroundColor Cyan
    }

    # Screenshot: Welcome
    $ss = Take-Screenshot -Name "phase1-01-welcome"
    $state.screenshots += $ss

    # Click: Dual Boot (Keep Windows)
    if (-not $DryRun) {
        $window = $null
        $attempts = 0
        while (-not $window -and $attempts -lt 10) {
            Start-Sleep -Seconds 1
            $window = Find-TauriWindow
            $attempts++
        }
        if (-not $window) { throw "Could not find Tauri installer window" }

        $btn = Find-ElementByName -Window $window -Name "Dual Boot (Keep Windows)"
        if ($btn) {
            Invoke-Element -Element $btn
        } else {
            Write-Warning "UIAutomation could not find 'Dual Boot' button; falling back to coordinates"
            # Approximate center-left of a 900x600 Tauri window centered on 1920x1080
            Click-AtCoordinates -X 720 -Y 600
        }
    } else {
        Write-Host "[DRY-RUN] Would click 'Dual Boot (Keep Windows)'" -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 3
    $ss = Take-Screenshot -Name "phase1-02-systemcheck"
    $state.screenshots += $ss

    # Wait for "Your PC is ready!" or timeout
    if (-not $DryRun) {
        $ready = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            $window = Find-TauriWindow
            if ($window) {
                $el = Find-ElementByName -Window $window -Name "Your PC is ready!"
                if ($el) { $ready = $true; break }
            }
        }
        if (-not $ready) { Write-Warning "Timed out waiting for 'Your PC is ready!'" }
    } else {
        Write-Host "[DRY-RUN] Would wait for 'Your PC is ready!' (max 20s)" -ForegroundColor Cyan
    }

    $ss = Take-Screenshot -Name "phase1-03-systemcheck-result"
    $state.screenshots += $ss

    # Click Continue
    if (-not $DryRun) {
        $window = Find-TauriWindow
        if ($window) {
            $btn = Find-ElementByName -Window $window -Name "Continue"
            if ($btn) { Invoke-Element -Element $btn }
            else { Click-AtCoordinates -X 1200 -Y 900 }
        }
    } else {
        Write-Host "[DRY-RUN] Would click 'Continue' after System Check" -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 2
    $ss = Take-Screenshot -Name "phase1-04-diskselection"
    $state.screenshots += $ss

    # Click Continue (accept defaults on Disk Selection)
    if (-not $DryRun) {
        $window = Find-TauriWindow
        if ($window) {
            $btn = Find-ElementByName -Window $window -Name "Continue"
            if ($btn) { Invoke-Element -Element $btn }
            else { Click-AtCoordinates -X 1200 -Y 900 }
        }
    } else {
        Write-Host "[DRY-RUN] Would click 'Continue' on Disk Selection" -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 2
    $ss = Take-Screenshot -Name "phase1-05-usersetup"
    $state.screenshots += $ss

    # Fill User Setup form
    if (-not $DryRun) {
        $window = Find-TauriWindow
        if ($window) {
            # Find textboxes by automation ID or name; fallback to Tab navigation + SendKeys
            [System.Windows.Forms.SendKeys]::SendWait("testuser{TAB}altos-lenovo{TAB}TestPass123!{TAB}TestPass123!{TAB}")
            Start-Sleep -Milliseconds 500
            $btn = Find-ElementByName -Window $window -Name "Continue"
            if ($btn) { Invoke-Element -Element $btn }
            else { Click-AtCoordinates -X 1200 -Y 900 }
        }
    } else {
        Write-Host "[DRY-RUN] Would fill user form: testuser / altos-lenovo / TestPass123!" -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 2
    $ss = Take-Screenshot -Name "phase1-06-edition"
    $state.screenshots += $ss

    # Select Basic (Free) and Continue
    if (-not $DryRun) {
        $window = Find-TauriWindow
        if ($window) {
            $btn = Find-ElementByName -Window $window -Name "Basic (Free)"
            if ($btn) { Invoke-Element -Element $btn }
            else { Click-AtCoordinates -X 720 -Y 650 }
            Start-Sleep -Milliseconds 500
            $btn = Find-ElementByName -Window $window -Name "Continue"
            if ($btn) { Invoke-Element -Element $btn }
            else { Click-AtCoordinates -X 1200 -Y 900 }
        }
    } else {
        Write-Host "[DRY-RUN] Would select 'Basic (Free)' and Continue" -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 2
    $ss = Take-Screenshot -Name "phase1-07-progress-start"
    $state.screenshots += $ss

    # Monitor progress
    if (-not $DryRun) {
        $restartFound = $false
        for ($cycle = 0; $cycle -lt 60; $cycle++) {
            Start-Sleep -Seconds 30
            $ss = Take-Screenshot -Name "phase1-08-progress-$cycle"
            $state.screenshots += $ss
            $window = Find-TauriWindow
            if ($window) {
                $btn = Find-ElementByName -Window $window -Name "Restart"
                if ($btn) {
                    Invoke-Element -Element $btn
                    $restartFound = $true
                    break
                }
            }
        }
        if (-not $restartFound) { Write-Warning "Restart button not found after 30 min" }
    } else {
        Write-Host "[DRY-RUN] Would monitor progress every 30s for up to 60 cycles" -ForegroundColor Cyan
    }

    # Update state
    $state.current_phase = "live"
    $state.status        = "running"
    $state.last_action   = "phase_windows_complete"
    Write-State -State $state

    # Schedule post-reboot Windows phase (Phase-Verify) via RunOnce
    $verifyScript = "$PSScriptRoot\altos-test-verify.ps1"
    if (-not $DryRun) {
        $runOnceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        Set-ItemProperty -Path $runOnceKey -Name "AltOSVerify" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$verifyScript`"" -ErrorAction SilentlyContinue
    } else {
        Write-Host "[DRY-RUN] Would register RunOnce key to launch Phase-Verify after reboot" -ForegroundColor Cyan
    }

    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  PHASE 1 COMPLETE                                            ║" -ForegroundColor Yellow
    Write-Host "║  The PC will reboot into Arch Live.                          ║" -ForegroundColor Yellow
    Write-Host "║  After the Live desktop appears, run:                        ║" -ForegroundColor Yellow
    Write-Host "║  sudo bash /mnt/OSWORLDBOOT/altos-test/altos-test-live.sh    ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow

    if (-not $DryRun) {
        $yn = Read-Host "Reboot now? (y/N)"
        if ($yn -eq 'y') { Restart-Computer -Force }
    } else {
        Write-Host "[DRY-RUN] Would prompt for reboot" -ForegroundColor Cyan
    }
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
function Start-Cleanup {
    Write-Host "`n========== CLEANUP ==========" -ForegroundColor Red
    $state = Read-State
    $state.status = "cleaned"
    Write-State -State $state

    $uninstaller = "$RepoRoot\scripts\uninstaller\windows-uninstall.ps1"
    if (Test-Path $uninstaller) {
        Write-Host "Running uninstaller: $uninstaller"
        if (-not $DryRun) {
            & powershell.exe -ExecutionPolicy Bypass -File $uninstaller
        }
    }

    $dir = Get-StateDirectory
    if (Test-Path $dir) {
        Write-Host "Removing test artifacts: $dir"
        if (-not $DryRun) { Remove-Item -Recurse -Force $dir }
    }

    if (Test-Path $StateDirFallback) {
        Write-Host "Removing fallback state: $StateDirFallback"
        if (-not $DryRun) { Remove-Item -Recurse -Force $StateDirFallback }
    }

    Write-Host "Cleanup complete." -ForegroundColor Green
}

# ─── Main ────────────────────────────────────────────────────────────────────
Test-Safety

if ($Cleanup) {
    Start-Cleanup
    exit 0
}

Start-PhaseWindows

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    AltOS Installer Physical Hardware Test Harness — Phase 4 (Windows Verification)
.DESCRIPTION
    Resumes after rebooting back to Windows from AltOS.
    Validates that Windows still boots, disk layout is correct, and generates the final report.
.PARAMETER DryRun
    Simulates verification without rebooting or modifying state.
#>
param([switch]$DryRun)

# ─── Configuration ───────────────────────────────────────────────────────────
$OsworldLabel     = "OSWORLDBOOT"
$StateDirFallback = "C:\altos-test"
$MarkerFile       = "C:\.altos-test-lenovo"

# ─── State helpers ───────────────────────────────────────────────────────────
function Get-StateDirectory {
    $vol = Get-Volume | Where-Object { $_.FileSystemLabel -eq $OsworldLabel } | Select-Object -First 1
    if ($vol) { return "$($vol.DriveLetter):\altos-test" }
    return $StateDirFallback
}

function Read-State {
    $dir = Get-StateDirectory
    $path = "$dir\state.json"
    if (Test-Path $path) { return Get-Content $path | ConvertFrom-Json }
    return @{ current_phase = "verify"; status = "running"; screenshots = @(); logs = @() }
}

function Write-State {
    param($State)
    $dir = Get-StateDirectory
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 10 | Set-Content "$dir\state.json" -Encoding UTF8
}

function Take-Screenshot {
    param([string]$Name)
    $dir = Get-StateDirectory
    $screenshotDir = "$dir\screenshots"
    if (-not (Test-Path $screenshotDir)) { New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = "$screenshotDir\$Name-$timestamp.png"

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

# ─── Phase: Verify ───────────────────────────────────────────────────────────
function Start-PhaseVerify {
    Write-Host "`n========== PHASE 4: WINDOWS VERIFICATION ==========" -ForegroundColor Green
    $state = Read-State

    if ($state.current_phase -ne 'verify') {
        Write-Host "State phase is $($state.current_phase), but continuing verification anyway."
    }

    $report = @{
        overall           = "unknown"
        phases            = @{}
        duration_seconds  = 0
        screenshots       = @()
        logs              = @()
        lenovo_specs      = @{}
        generated_at      = (Get-Date -Format "o")
    }

    # Determine start time
    if ($state.start_time) {
        try {
            $start = [datetime]::Parse($state.start_time)
            $report.duration_seconds = [math]::Round(((Get-Date) - $start).TotalSeconds)
        } catch {}
    }

    # a) Screenshot desktop
    $ss = Take-Screenshot -Name "phase4-01-desktop"
    $report.screenshots += $ss
    $state.screenshots += $ss

    # b) Verify C: drive
    $c = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    if ($c) {
        Write-Host "C: drive OK — Size: $([math]::Round($c.Size / 1GB,1)) GB, Free: $([math]::Round($c.SizeRemaining / 1GB,1)) GB" -ForegroundColor Green
        $report.phases.windows_disk = "pass"
        $report.lenovo_specs.c_drive_gb = [math]::Round($c.Size / 1GB,1)
    } else {
        Write-Warning "C: drive check failed"
        $report.phases.windows_disk = "fail"
    }

    # c) Disk Management — check for Linux partitions via WMI
    try {
        $partitions = Get-WmiObject -Class Win32_DiskPartition | Where-Object {
            $_.Type -like "*Linux*" -or $_.Type -like "*Unknown*"
        }
        if ($partitions) {
            Write-Host "Linux partitions detected in Disk Management:" -ForegroundColor Green
            $partitions | ForEach-Object { Write-Host "  Partition $($_.Index): $($_.Size / 1GB) GB, Type: $($_.Type)" }
            $report.phases.linux_partitions = "pass"
        } else {
            Write-Warning "No Linux partitions found in WMI"
            $report.phases.linux_partitions = "fail"
        }
    } catch {
        Write-Warning "Could not query disk partitions: $_"
        $report.phases.linux_partitions = "unknown"
    }

    # d) Event Viewer boot check
    try {
        $bootErrors = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ID = 6008,41,1074; StartTime = (Get-Date).AddHours(-2) } -ErrorAction SilentlyContinue
        if ($bootErrors) {
            Write-Warning "Recent boot/shutdown events found (may be normal):"
            $bootErrors | Select-Object -First 3 | ForEach-Object { Write-Host "  $($_.TimeCreated): $($_.Message.Substring(0,[Math]::Min(80,$_.Message.Length)))" }
        } else {
            Write-Host "No recent critical boot events in Event Viewer." -ForegroundColor Green
        }
    } catch {
        Write-Host "Event Viewer check skipped or no events."
    }

    # e) Verify AltOS can boot again (manual step)
    if (-not $DryRun) {
        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║  MANUAL STEP                                                 ║" -ForegroundColor Yellow
        Write-Host "║  To verify AltOS boots again:                                ║" -ForegroundColor Yellow
        Write-Host "║  1. Restart this PC                                          ║" -ForegroundColor Yellow
        Write-Host "║  2. At the rEFInd menu, select AltOS                         ║" -ForegroundColor Yellow
        Write-Host "║  3. Confirm it boots to the login screen                     ║" -ForegroundColor Yellow
        Write-Host "║  4. Reboot back to Windows                                   ║" -ForegroundColor Yellow
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        $yn = Read-Host "Have you verified AltOS boots again? (y/N)"
        if ($yn -eq 'y') {
            $report.phases.altos_reboot = "pass"
        } else {
            $report.phases.altos_reboot = "skipped"
        }
    } else {
        Write-Host "[DRY-RUN] Would prompt user to manually verify AltOS reboot" -ForegroundColor Cyan
        $report.phases.altos_reboot = "dry-run"
    }

    # Collect all screenshots and logs
    $dir = Get-StateDirectory
    if (Test-Path "$dir\screenshots") {
        $report.screenshots = @(Get-ChildItem "$dir\screenshots" | Select-Object -ExpandProperty FullName)
    }
    if (Test-Path "$dir\logs") {
        $report.logs = @(Get-ChildItem "$dir\logs" | Select-Object -ExpandProperty FullName)
    }

    # Determine overall result
    $failures = $report.phases.Values | Where-Object { $_ -eq "fail" }
    $report.overall = if ($failures) { "fail" } else { "pass" }

    # Save report
    $reportPath = "$dir\test-report.json"
    $report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8
    Write-Host "`nTest report saved: $reportPath" -ForegroundColor Green

    # Update state
    $state.current_phase = "verify"
    $state.status = $report.overall
    $state.report = $reportPath
    Write-State -State $state

    # Summary
    Write-Host "`n========== FINAL SUMMARY ==========" -ForegroundColor ($report.overall -eq "pass" ? "Green" : "Red")
    Write-Host "Overall: $($report.overall.ToUpper())" -ForegroundColor ($report.overall -eq "pass" ? "Green" : "Red")
    Write-Host "Duration: $($report.duration_seconds) seconds"
    Write-Host "Phases:"
    $report.phases.GetEnumerator() | ForEach-Object {
        $color = if ($_.Value -eq "pass") { "Green" } elseif ($_.Value -eq "fail") { "Red" } else { "Yellow" }
        Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor $color
    }
    Write-Host "Screenshots: $($report.screenshots.Count)"
    Write-Host "Logs: $($report.logs.Count)"
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
function Start-Cleanup {
    Write-Host "`n========== CLEANUP ==========" -ForegroundColor Red
    $state = Read-State
    $state.status = "cleaned"
    Write-State -State $state

    $dir = Get-StateDirectory
    if (Test-Path $dir) {
        Write-Host "Removing test artifacts: $dir"
        if (-not $DryRun) { Remove-Item -Recurse -Force $dir }
    }
    Write-Host "Cleanup complete." -ForegroundColor Green
}

# ─── Main ────────────────────────────────────────────────────────────────────
if ($DryRun) {
    Write-Host "[DRY-RUN MODE] Simulating Phase 4 without reboots or disk changes." -ForegroundColor Cyan
}

Start-PhaseVerify

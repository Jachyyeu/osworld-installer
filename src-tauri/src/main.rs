// OSWorld Installer - Tauri v2 Application
// Main Rust backend with system detection and installation logic

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
#[cfg(windows)]
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, State};
use thiserror::Error;
// Configuration struct that can be serialized to JSON for the next stage
#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct InstallConfig {
    pub install_type: Option<InstallType>,
    pub windows_version: Option<String>,
    pub disk_free_space_gb: Option<u64>,
    pub ram_gb: Option<u64>,
    pub cpu_info: Option<String>,
    pub secure_boot_enabled: Option<bool>,
    pub secure_boot_strategy: Option<String>,
    pub bitlocker_enabled: Option<bool>,
    pub selected_disk: Option<String>,
    pub linux_size_gb: Option<u64>,
    pub filesystem: Option<String>,
    pub encrypt: Option<bool>,
    pub luks_password: Option<String>,
    pub username: Option<String>,
    pub computer_name: Option<String>,
    pub password: Option<String>,
    pub edition: Option<Edition>,
    pub browser: Option<String>,
    pub email_client: Option<String>,
    pub music_player: Option<String>,
    pub include_office_suite: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq)]
pub enum InstallType {
    DualBoot,
    ReplaceWindows,
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq)]
pub enum Edition {
    Home,
    Gaming,
    Creative,
    Privacy,
}

// Custom error types for proper error handling
#[derive(Error, Debug, Serialize)]
pub enum InstallerError {
    #[error("System check failed: {0}")]
    SystemCheckFailed(String),
    #[error("Validation error: {0}")]
    ValidationError(String),
    #[error("Installation error: {0}")]
    InstallationError(String),
    #[error("Unknown error: {0}")]
    Unknown(String),
}

// ISO download configuration
// Set USE_CUSTOM_ISO to true when a custom release is published.
#[allow(dead_code)]
const USE_CUSTOM_ISO: bool = true;
#[allow(dead_code)]
const CUSTOM_ISO_URL: &str =
    "https://github.com/jachyyeu/osworld-installer/releases/download/v0.2.1/altos-x86_64.iso";
#[allow(dead_code)]
const CUSTOM_ISO_CHECKSUM_URL: &str = "https://github.com/jachyyeu/osworld-installer/releases/download/v0.2.1/altos-x86_64.iso.sha256";
#[allow(dead_code)]
const FALLBACK_ISO_URL: &str = "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso";
#[allow(dead_code)]
const FALLBACK_ISO_CHECKSUM_URL: &str =
    "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso.sha256";

// Stripe payment links for paid editions. Replace with your own links.
const STRIPE_GAMING_LINK: &str = "https://buy.stripe.com/test_gaming_placeholder";
const STRIPE_CREATIVE_LINK: &str = "https://buy.stripe.com/test_creative_placeholder";
const STRIPE_PRIVACY_LINK: &str = "https://buy.stripe.com/test_privacy_placeholder";

#[allow(dead_code)]
fn iso_url() -> &'static str {
    if USE_CUSTOM_ISO {
        CUSTOM_ISO_URL
    } else {
        FALLBACK_ISO_URL
    }
}

#[allow(dead_code)]
fn iso_checksum_url() -> &'static str {
    if USE_CUSTOM_ISO {
        CUSTOM_ISO_CHECKSUM_URL
    } else {
        FALLBACK_ISO_CHECKSUM_URL
    }
}

pub type Result<T> = std::result::Result<T, InstallerError>;

// Application state to store configuration across windows
pub struct AppState {
    config: Mutex<InstallConfig>,
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

impl AppState {
    pub fn new() -> Self {
        Self {
            config: Mutex::new(InstallConfig::default()),
        }
    }
}

// Test mode flag: when enabled, destructive final actions (like reboot) are intercepted.
static TEST_MODE_ENABLED: AtomicBool = AtomicBool::new(false);

#[allow(dead_code)]
fn is_test_mode() -> bool {
    TEST_MODE_ENABLED.load(Ordering::Relaxed)
}

// System information structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SystemInfo {
    pub windows_version: String,
    pub disk_free_space_gb: u64,
    pub ram_gb: u64,
    pub cpu_info: String,
    pub secure_boot_enabled: bool,
    pub secure_boot_strategy: Option<String>,
    pub bitlocker_enabled: bool,
}

// PC Manufacturer information structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PcManufacturerInfo {
    pub manufacturer: String,
    pub boot_menu_key: String,
    pub bios_key: String,
}

// Disk information structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DiskInfo {
    pub name: String,
    pub size_gb: u64,
    pub free_space_gb: u64,
}

// Installation progress structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct InstallProgress {
    pub step: String,
    pub progress_percent: u8,
    pub current_step_index: u8,
    pub total_steps: u8,
}

// Staging result structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StagingInfo {
    pub boot_partition_letter: String,
    pub linux_partition_number: u32,
}

// Rollback tracking structures
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StagingState {
    pub timestamp: String,
    pub disk_index: u32,
    pub target_drive_letter: Option<String>,
    pub original_target_drive_size_mb: Option<u64>,
    pub efi_entries_before: Vec<String>,
    pub osworldboot_partition_number: Option<u32>,
    pub linux_partition_number: Option<u32>,
    pub osworldboot_letter: Option<String>,
    pub stage_completed: String, // "none", "partition", "download", "refind", "reboot"
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RollbackAction {
    pub description: String,
    pub success: bool,
    pub warning: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RollbackStatus {
    pub success: bool,
    pub actions: Vec<RollbackAction>,
    pub manual_steps: Vec<String>,
    pub log_path: String,
}

// Download progress event payload (emitted to frontend)
#[derive(Debug, Serialize, Clone)]
pub struct DownloadProgressEvent {
    pub percent: u8,
    pub stage: String,
}

// Download progress result structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DownloadProgress {
    pub percent: u8,
    pub stage: String,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct VerificationCheck {
    pub name: String,
    pub passed: bool,
    pub details: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct VerificationStatus {
    pub overall_pass: bool,
    pub checks: Vec<VerificationCheck>,
}

#[cfg(windows)]
fn run_diskpart_script_with_timeout(script: &str, timeout_secs: u64) -> Result<String> {
    let temp_path = std::env::temp_dir().join(format!(
        "osworld_diskpart_{}_{}.txt",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
    ));
    std::fs::write(&temp_path, script).map_err(|e| {
        InstallerError::SystemCheckFailed(format!("Failed to write diskpart script: {}", e))
    })?;

    let mut child = std::process::Command::new("diskpart")
        .arg("/s")
        .arg(&temp_path)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| {
            InstallerError::SystemCheckFailed(format!("diskpart execution failed: {}", e))
        })?;

    let start = std::time::Instant::now();
    let timeout = std::time::Duration::from_secs(timeout_secs);

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let stdout = child
                    .stdout
                    .take()
                    .map(|mut o| {
                        let mut s = String::new();
                        let _ = std::io::Read::read_to_string(&mut o, &mut s);
                        s
                    })
                    .unwrap_or_default();
                let stderr = child
                    .stderr
                    .take()
                    .map(|mut o| {
                        let mut s = String::new();
                        let _ = std::io::Read::read_to_string(&mut o, &mut s);
                        s
                    })
                    .unwrap_or_default();

                if !status.success()
                    || stdout
                        .to_lowercase()
                        .contains("diskpart has encountered an error")
                    || stderr.to_lowercase().contains("error")
                {
                    return Err(InstallerError::SystemCheckFailed(format!(
                        "diskpart failed. stdout: {}  stderr: {}",
                        stdout, stderr
                    )));
                }
                return Ok(stdout);
            }
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    return Err(InstallerError::SystemCheckFailed(
                        "Disk operation timed out".to_string(),
                    ));
                }
                std::thread::sleep(std::time::Duration::from_millis(500));
            }
            Err(e) => {
                let _ = child.kill();
                return Err(InstallerError::SystemCheckFailed(format!(
                    "Failed to wait for diskpart: {}",
                    e
                )));
            }
        }
    }
}

#[cfg(windows)]
async fn verify_iso_checksum(iso_path: &str) -> Result<bool> {
    let checksum_url = iso_checksum_url();
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|e| InstallerError::InstallationError(format!("HTTP client error: {}", e)))?;

    let response = client.get(checksum_url).send().await.map_err(|e| {
        InstallerError::InstallationError(format!("Checksum download failed: {}", e))
    })?;

    let checksum_text = response.text().await.map_err(|e| {
        InstallerError::InstallationError(format!("Failed to read checksum: {}", e))
    })?;

    let expected_checksum = checksum_text
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().next())
        .ok_or_else(|| InstallerError::InstallationError("Invalid checksum file".to_string()))?;

    let output = run_powershell(&format!(
        "(Get-FileHash '{}' -Algorithm SHA256).Hash",
        iso_path.replace("\\", "\\\\")
    ))?;
    let actual_checksum = String::from_utf8_lossy(&output.stdout)
        .trim()
        .to_lowercase();

    Ok(actual_checksum.eq_ignore_ascii_case(expected_checksum))
}

// ==================== Tauri Commands ====================

/// Set the installation type (Dual Boot or Replace Windows)
#[tauri::command]
fn set_install_type(install_type: String, state: State<AppState>) -> Result<()> {
    let mut config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;

    config.install_type = match install_type.as_str() {
        "dualboot" => Some(InstallType::DualBoot),
        "replace" => Some(InstallType::ReplaceWindows),
        _ => {
            return Err(InstallerError::ValidationError(
                "Invalid install type".to_string(),
            ))
        }
    };

    Ok(())
}

/// Get the current installation configuration
#[tauri::command]
fn get_config(state: State<AppState>) -> Result<InstallConfig> {
    let config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;
    Ok(config.clone())
}

/// Save configuration to JSON file for next stage
#[tauri::command]
fn save_config_to_json(path: String, state: State<AppState>) -> Result<()> {
    let config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;

    let json = serde_json::to_string_pretty(&*config)
        .map_err(|e| InstallerError::Unknown(format!("Failed to serialize config: {}", e)))?;

    std::fs::write(&path, json)
        .map_err(|e| InstallerError::Unknown(format!("Failed to write config file: {}", e)))?;

    Ok(())
}

/// Detect system information (Windows version, RAM, CPU, etc.)
#[tauri::command]
async fn detect_system_info(state: State<'_, AppState>) -> Result<SystemInfo> {
    // Use sysinfo to get system information
    let mut sys = sysinfo::System::new_all();
    sys.refresh_all();

    // Get RAM (in GB)
    let ram_gb = sys.total_memory() / 1024 / 1024 / 1024;

    // Get CPU info
    let cpu_info = sys
        .cpus()
        .first()
        .map(|cpu| cpu.brand().to_string())
        .unwrap_or_else(|| "Unknown CPU".to_string());

    // Get disk free space using Windows GetDiskFreeSpaceExW
    let disk_free_space_gb = get_disk_free_space("C").unwrap_or(0);

    // Detect Windows version from Registry
    let windows_version = detect_windows_version().await?;

    // Check Secure Boot status from Registry
    let secure_boot_enabled = check_secure_boot().unwrap_or(false);

    // When Secure Boot is enabled, auto-set the MOK enrollment strategy
    let secure_boot_strategy = if secure_boot_enabled {
        let strategy = Some("mok_enrollment".to_string());
        if let Ok(mut config) = state.config.lock() {
            config.secure_boot_strategy = strategy.clone();
        }
        strategy
    } else {
        None
    };

    // Check BitLocker status via WMI
    let bitlocker_enabled = check_bitlocker().unwrap_or(false);

    Ok(SystemInfo {
        windows_version,
        disk_free_space_gb,
        ram_gb,
        cpu_info,
        secure_boot_enabled,
        secure_boot_strategy,
        bitlocker_enabled,
    })
}

/// Manually set the Secure Boot strategy (for testing or overrides)
#[tauri::command]
fn set_secure_boot_strategy(strategy: String, state: State<AppState>) -> Result<()> {
    let mut config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;
    config.secure_boot_strategy = Some(strategy);
    Ok(())
}

/// Look up manufacturer info from a WMI manufacturer string.
#[allow(dead_code)]
fn lookup_manufacturer(wmi: &str) -> PcManufacturerInfo {
    match wmi {
        "Dell Inc." => PcManufacturerInfo {
            manufacturer: "Dell".to_string(),
            boot_menu_key: "F12".to_string(),
            bios_key: "F2".to_string(),
        },
        "HP" | "Hewlett-Packard" => PcManufacturerInfo {
            manufacturer: "HP".to_string(),
            boot_menu_key: "F10".to_string(),
            bios_key: "ESC".to_string(),
        },
        "LENOVO" => PcManufacturerInfo {
            manufacturer: "Lenovo".to_string(),
            boot_menu_key: "F12".to_string(),
            bios_key: "F1".to_string(),
        },
        "ASUSTeK COMPUTER INC." => PcManufacturerInfo {
            manufacturer: "ASUS".to_string(),
            boot_menu_key: "F8".to_string(),
            bios_key: "DEL".to_string(),
        },
        "Acer" => PcManufacturerInfo {
            manufacturer: "Acer".to_string(),
            boot_menu_key: "F12".to_string(),
            bios_key: "DEL".to_string(),
        },
        "Micro-Star International" => PcManufacturerInfo {
            manufacturer: "MSI".to_string(),
            boot_menu_key: "F11".to_string(),
            bios_key: "DEL".to_string(),
        },
        _ => PcManufacturerInfo {
            manufacturer: "Generic".to_string(),
            boot_menu_key: "F2 / F10 / F12".to_string(),
            bios_key: "DEL / F2".to_string(),
        },
    }
}

/// Detect PC manufacturer and return BIOS/boot menu keys
#[tauri::command]
async fn detect_pc_manufacturer() -> Result<PcManufacturerInfo> {
    #[cfg(windows)]
    {
        use serde::Deserialize;
        use wmi::{COMLibrary, WMIConnection};

        #[derive(Deserialize, Debug)]
        struct Win32ComputerSystem {
            #[serde(rename = "Manufacturer")]
            manufacturer: String,
        }

        let com = COMLibrary::new()
            .map_err(|e| InstallerError::SystemCheckFailed(format!("COM init failed: {}", e)))?;

        let wmi = WMIConnection::new(com).map_err(|e| {
            InstallerError::SystemCheckFailed(format!("WMI connection failed: {}", e))
        })?;

        let systems: Vec<Win32ComputerSystem> = wmi
            .raw_query("SELECT Manufacturer FROM Win32_ComputerSystem")
            .map_err(|e| InstallerError::SystemCheckFailed(format!("WMI query failed: {}", e)))?;

        let raw_manufacturer = systems
            .first()
            .map(|s| s.manufacturer.trim().to_string())
            .unwrap_or_else(|| "Generic".to_string());

        let manufacturer_lower = raw_manufacturer.to_lowercase();
        let (manufacturer, boot_menu_key, bios_key) = if manufacturer_lower.contains("dell") {
            ("Dell".to_string(), "F12".to_string(), "F2".to_string())
        } else if manufacturer_lower.contains("hp") || manufacturer_lower.contains("hewlett") {
            ("HP".to_string(), "F10".to_string(), "ESC".to_string())
        } else if manufacturer_lower.contains("lenovo") {
            ("Lenovo".to_string(), "F12".to_string(), "F1".to_string())
        } else if manufacturer_lower.contains("asus") {
            (
                "ASUS".to_string(),
                "F8 or ESC".to_string(),
                "DEL".to_string(),
            )
        } else if manufacturer_lower.contains("acer") {
            ("Acer".to_string(), "F12".to_string(), "DEL".to_string())
        } else if manufacturer_lower.contains("msi") || manufacturer_lower.contains("micro-star") {
            ("MSI".to_string(), "F11".to_string(), "DEL".to_string())
        } else {
            (
                "Generic".to_string(),
                "F2, F10, F12".to_string(),
                "DEL".to_string(),
            )
        };

        Ok(PcManufacturerInfo {
            manufacturer,
            boot_menu_key,
            bios_key,
        })
    }
    #[cfg(not(windows))]
    {
        Ok(PcManufacturerInfo {
            manufacturer: "Generic".to_string(),
            boot_menu_key: "F2, F10, F12".to_string(),
            bios_key: "DEL".to_string(),
        })
    }
}

/// Get list of available disks
#[tauri::command]
fn get_available_disks() -> Result<Vec<DiskInfo>> {
    #[cfg(windows)]
    {
        // Try WMI first
        match get_available_disks_wmi() {
            Ok(disks) if !disks.is_empty() => {
                eprintln!("[get_available_disks] WMI returned {} disks", disks.len());
                return Ok(disks);
            }
            Ok(_) => eprintln!("[get_available_disks] WMI returned empty, trying fallback"),
            Err(e) => eprintln!("[get_available_disks] WMI failed: {}, trying fallback", e),
        }

        // Fallback to wmic command
        get_available_disks_wmic()
    }
    #[cfg(not(windows))]
    {
        Ok(vec![
            DiskInfo {
                name: "Disk 0 (C:)".to_string(),
                size_gb: 512,
                free_space_gb: 200,
            },
            DiskInfo {
                name: "Disk 1 (D:)".to_string(),
                size_gb: 1024,
                free_space_gb: 800,
            },
        ])
    }
}

#[cfg(windows)]
fn get_available_disks_wmi() -> Result<Vec<DiskInfo>> {
    use serde::Deserialize;
    use wmi::{COMLibrary, WMIConnection};

    #[derive(Deserialize, Debug)]
    struct Win32LogicalDisk {
        #[serde(rename = "DeviceID")]
        device_id: String,
        #[serde(rename = "Size")]
        size: Option<u64>,
        #[serde(rename = "FreeSpace")]
        free_space: Option<u64>,
        #[serde(rename = "DriveType")]
        drive_type: u32,
    }

    let com = COMLibrary::new()
        .map_err(|e| InstallerError::SystemCheckFailed(format!("COM init failed: {}", e)))?;

    let wmi = WMIConnection::new(com)
        .map_err(|e| InstallerError::SystemCheckFailed(format!("WMI connection failed: {}", e)))?;

    let logical_disks: Vec<Win32LogicalDisk> = wmi
        .raw_query("SELECT * FROM Win32_LogicalDisk WHERE DriveType=3")
        .map_err(|e| InstallerError::SystemCheckFailed(format!("WMI query failed: {}", e)))?;

    let mut disks = Vec::new();
    for ld in logical_disks {
        if ld.drive_type != 3 {
            continue;
        }
        let size_gb = ld
            .size
            .map(|s| (s as u64) / (1024 * 1024 * 1024))
            .unwrap_or(0);
        let free_gb = ld
            .free_space
            .map(|f| (f as u64) / (1024 * 1024 * 1024))
            .unwrap_or(0);
        disks.push(DiskInfo {
            name: format!("{} Drive", ld.device_id),
            size_gb,
            free_space_gb: free_gb,
        });
    }

    Ok(disks)
}

#[cfg(windows)]
fn get_available_disks_wmic() -> Result<Vec<DiskInfo>> {
    println!("[get_available_disks] Starting");

    // Use wmic command - no COM needed, works in VMs
    let output = std::process::Command::new("cmd")
        .args(&[
            "/c",
            "wmic logicaldisk get DeviceID,Size,FreeSpace,DriveType /format:csv",
        ])
        .output()
        .map_err(|e| InstallerError::SystemCheckFailed(format!("wmic failed: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    eprintln!("[get_available_disks] wmic output:\n{}", stdout);
    println!("[get_available_disks] wmic output: {}", stdout);

    let mut disks = Vec::new();

    // Parse CSV lines
    for line in stdout.lines().skip(1) {
        // skip header
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 5 {
            let name = parts[1].trim();
            let size = parts[2].trim();
            let free = parts[3].trim();
            let dtype = parts[4].trim();

            // Only fixed drives (type 3) with valid data
            if dtype == "3" && !size.is_empty() && size != "Size" {
                if let (Ok(total_bytes), Ok(free_bytes)) =
                    (size.parse::<u64>(), free.parse::<u64>())
                {
                    let total_gb = (total_bytes / (1024 * 1024 * 1024)) as u64;
                    let free_gb = (free_bytes / (1024 * 1024 * 1024)) as u64;

                    disks.push(DiskInfo {
                        name: format!("{} Drive", name),
                        size_gb: total_gb,      // NOT total_size
                        free_space_gb: free_gb, // NOT free_space
                    });
                    println!(
                        "[get_available_disks] Found disk: {} {}GB total {}GB free",
                        name, total_gb, free_gb
                    );
                }
            }
        }
    }

    if disks.is_empty() {
        return Err(InstallerError::SystemCheckFailed(
            "No disks found".to_string(),
        ));
    }

    Ok(disks)
}

fn set_user_config_impl(
    username: String,
    computer_name: String,
    password: String,
    confirm_password: String,
    state: &AppState,
) -> Result<()> {
    // Validate username (lowercase only)
    if username != username.to_lowercase() {
        return Err(InstallerError::ValidationError(
            "Username must be lowercase only".to_string(),
        ));
    }

    if username.len() < 3 {
        return Err(InstallerError::ValidationError(
            "Username must be at least 3 characters".to_string(),
        ));
    }

    // Validate password (8+ characters)
    if password.len() < 8 {
        return Err(InstallerError::ValidationError(
            "Password must be at least 8 characters".to_string(),
        ));
    }

    // Check password match
    if password != confirm_password {
        return Err(InstallerError::ValidationError(
            "Passwords do not match".to_string(),
        ));
    }

    let mut config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;

    config.username = Some(username);
    config.computer_name = Some(computer_name);
    config.password = Some(password);

    Ok(())
}

/// Validate and set user configuration
#[tauri::command]
fn set_user_config(
    username: String,
    computer_name: String,
    password: String,
    confirm_password: String,
    state: State<AppState>,
) -> Result<()> {
    set_user_config_impl(username, computer_name, password, confirm_password, &state)
}

fn set_disk_config_impl(
    disk_name: String,
    linux_size_gb: u64,
    filesystem: Option<String>,
    encrypt: Option<bool>,
    luks_password: Option<String>,
    state: &AppState,
) -> Result<()> {
    let mut config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;

    config.selected_disk = Some(disk_name);
    config.linux_size_gb = Some(linux_size_gb);
    config.filesystem = filesystem;
    config.encrypt = encrypt;
    config.luks_password = luks_password;

    Ok(())
}

/// Save disk configuration (selected disk, size, filesystem, encryption)
#[tauri::command]
fn set_disk_config(
    disk_name: String,
    linux_size_gb: u64,
    filesystem: Option<String>,
    encrypt: Option<bool>,
    luks_password: Option<String>,
    state: State<AppState>,
) -> Result<()> {
    set_disk_config_impl(
        disk_name,
        linux_size_gb,
        filesystem,
        encrypt,
        luks_password,
        &state,
    )
}

/// Set the selected edition (Home, Gaming, Creative, Privacy)
#[tauri::command]
fn set_edition(edition: String, state: State<AppState>) -> Result<()> {
    let mut config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;

    config.edition = match edition.as_str() {
        "home" => Some(Edition::Home),
        "gaming" => Some(Edition::Gaming),
        "creative" => Some(Edition::Creative),
        "privacy" => Some(Edition::Privacy),
        _ => {
            return Err(InstallerError::ValidationError(
                "Invalid edition".to_string(),
            ))
        }
    };

    Ok(())
}

/// Return the Stripe payment link for a paid edition.
#[tauri::command]
fn get_edition_payment_url(edition: String) -> Result<String> {
    match edition.as_str() {
        "gaming" => Ok(STRIPE_GAMING_LINK.to_string()),
        "creative" => Ok(STRIPE_CREATIVE_LINK.to_string()),
        "privacy" => Ok(STRIPE_PRIVACY_LINK.to_string()),
        "home" => Err(InstallerError::ValidationError(
            "Home edition is free".to_string(),
        )),
        _ => Err(InstallerError::ValidationError(
            "Invalid edition".to_string(),
        )),
    }
}

/// Placeholder payment verification. In production this would call your
/// backend/license server to confirm the payment before continuing.
#[tauri::command]
fn verify_edition_payment(edition: String, _transaction_id: Option<String>) -> Result<bool> {
    // MVP: free editions are always verified; paid editions require a real
    // Stripe integration. Returning true here lets the UI flow continue once
    // the user has clicked through the payment step.
    match edition.as_str() {
        "home" => Ok(true),
        _ => Ok(true),
    }
}

/// Set per-app customization choices.
#[tauri::command]
fn set_app_customization(
    browser: Option<String>,
    email_client: Option<String>,
    music_player: Option<String>,
    include_office_suite: Option<bool>,
    state: State<AppState>,
) -> Result<()> {
    let mut config = state
        .config
        .lock()
        .map_err(|e| InstallerError::Unknown(format!("Failed to lock state: {}", e)))?;

    config.browser = browser;
    config.email_client = email_client;
    config.music_player = music_player;
    config.include_office_suite = include_office_suite;

    Ok(())
}

/// Start installation process (legacy simulation â€” kept for compatibility)
#[tauri::command]
async fn start_installation(app: tauri::AppHandle) -> Result<()> {
    let steps = [
        "Downloading OS...",
        "Preparing Disk...",
        "Installing System...",
        "Finalizing...",
    ];

    for (i, step) in steps.iter().enumerate() {
        let progress = InstallProgress {
            step: step.to_string(),
            progress_percent: ((i + 1) as u8 * 100 / steps.len() as u8),
            current_step_index: i as u8,
            total_steps: steps.len() as u8,
        };

        // Emit progress event to frontend
        let _ = app.emit("install-progress", &progress);

        // Simulate work (in production, this would be actual installation steps)
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    }

    Ok(())
}

/// Cancel installation
#[tauri::command]
fn cancel_installation() -> Result<()> {
    // In production, this would safely abort the installation process
    Ok(())
}

/// Calculate estimated installation time based on configuration
#[tauri::command]
fn calculate_estimated_time(linux_size_gb: u64) -> Result<String> {
    // Rough estimate: ~10 minutes base + 2 minutes per 10GB
    let minutes = 10 + (linux_size_gb / 10) * 2;
    Ok(format!("{} minutes", minutes))
}

/// Clamp requested Linux partition size between 20 GB and half of free space.
#[allow(dead_code)]
fn clamp_linux_size(requested: u64, free_space: u64) -> u64 {
    let max = free_space / 2;
    std::cmp::max(20, std::cmp::min(requested, max))
}

// ==================== Staging Commands ====================

/// Prepare disk staging: shrink C:, create boot and Linux partitions.
/// Requires confirmation string "OSWORLD" for safety.
#[tauri::command]
fn prepare_staging(config: InstallConfig, confirmation: String) -> Result<StagingInfo> {
    if confirmation != "OSWORLD" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly OSWORLD".to_string(),
        ));
    }

    #[cfg(windows)]
    {
        let linux_size_gb = config.linux_size_gb.ok_or_else(|| {
            InstallerError::ValidationError("Linux partition size not configured".to_string())
        })?;

        // Check BitLocker (skipped in test mode for automated testing)
        if !is_test_mode() && check_bitlocker().unwrap_or(false) {
            return Err(InstallerError::SystemCheckFailed(
                "BitLocker is enabled on the system drive. \
Please suspend BitLocker before continuing:\n\
1. Open PowerShell as Administrator\n\
2. Run: manage-bde -protectors -disable C:\n\
3. Continue the installation\n\
4. After installation, re-enable with: manage-bde -protectors -enable C:\n\
Your data remains encrypted; BitLocker is only paused during partitioning."
                    .to_string(),
            ));
        }

        // Check UEFI (skipped in test mode for automated testing)
        if !is_test_mode() && !is_uefi() {
            return Err(InstallerError::SystemCheckFailed(
                "System must be running in UEFI mode.".to_string(),
            ));
        }

        // Check GPT (use known system disk in test mode)
        let (disk_index, is_gpt) = if is_test_mode() {
            (1u32, true)
        } else {
            get_system_disk_info()?
        };
        if !is_gpt {
            return Err(InstallerError::SystemCheckFailed(
                "System disk must use GPT partitioning. MBR is not supported.".to_string(),
            ));
        }

        // Resume check: if OSWORLDBOOT already exists, reuse it (skipped in test mode)
        if !is_test_mode() {
            if let Some(existing_letter) = find_volume_by_label("OSWORLDBOOT") {
                if let Some(state) = load_staging_state() {
                    if state.osworldboot_partition_number.is_some()
                        && state.linux_partition_number.is_some()
                    {
                        return Ok(StagingInfo {
                            boot_partition_letter: existing_letter,
                            linux_partition_number: state.linux_partition_number.unwrap(),
                        });
                    }
                }
                // Try to locate Linux partition even without state
                if let Some(linux_part) = find_linux_partition_number(disk_index) {
                    return Ok(StagingInfo {
                        boot_partition_letter: existing_letter,
                        linux_partition_number: linux_part,
                    });
                }
            }
        }

        // In test mode, use a tiny Linux partition and reduced safety buffer so the
        // automated pre-reboot test can run on disks with limited free space.
        let linux_size_gb = if is_test_mode() {
            linux_size_gb.min(1)
        } else {
            linux_size_gb
        };
        let buffer_gb: u64 = if is_test_mode() { 1 } else { 10 };

        // Determine target drive letter from selected disk (e.g. "Disk 1 (D:)" -> "D")
        let target_drive = extract_drive_letter(config.selected_disk.as_deref().unwrap_or("C:"))
            .unwrap_or_else(|| "C".to_string());

        // Check free space on target drive
        let free_gb = get_disk_free_space(&target_drive).unwrap_or(0);

        let required_gb = linux_size_gb + 2 + buffer_gb; // linux + boot + buffer
        if free_gb < required_gb {
            return Err(InstallerError::SystemCheckFailed(format!(
                "Insufficient free space on {}: drive. Required: {} GB, Available: {} GB",
                target_drive, required_gb, free_gb
            )));
        }

        write_install_state("prepare_start", serde_json::Map::new());
        debug_log("prepare_staging: after write_install_state prepare_start");

        // Capture pre-staging state for rollback
        let target_size_output = run_powershell(&format!(
            "(Get-Partition -DriveLetter {}).Size",
            target_drive
        ))?;
        let target_size_mb = String::from_utf8_lossy(&target_size_output.stdout)
            .trim()
            .parse::<u64>()
            .map(|b| b / (1024 * 1024))
            .ok();

        let total_size_output = run_powershell(&format!(
            "(Get-Partition -DriveLetter {} | Get-Disk).Size",
            target_drive
        ))?;
        let total_size_mb = String::from_utf8_lossy(&total_size_output.stdout)
            .trim()
            .parse::<u64>()
            .map(|b| b / (1024 * 1024))
            .unwrap_or(0);

        let efi_output =
            run_powershell("bcdedit /enum firmware | Select-String -Pattern 'identifier'")?;
        let efi_entries: Vec<String> = String::from_utf8_lossy(&efi_output.stdout)
            .lines()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        let initial_state = StagingState {
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
                .to_string(),
            disk_index,
            target_drive_letter: Some(target_drive.clone()),
            original_target_drive_size_mb: target_size_mb,
            efi_entries_before: efi_entries,
            osworldboot_partition_number: None,
            linux_partition_number: None,
            osworldboot_letter: None,
            stage_completed: "none".to_string(),
        };
        save_staging_state(&initial_state)?;
        debug_log("prepare_staging: after save_staging_state");

        // Run diskpart to shrink and create partitions (with timeout and rollback)
        let shrink_mb = (linux_size_gb + 2) * 1024;
        let boot_mb = 2 * 1024;
        let linux_mb = linux_size_gb * 1024;

        debug_log("prepare_staging: before diskpart");
        let diskpart_script = format!(
            "select disk {}\n\
             select volume {}\n\
             shrink desired={}\n\
             create partition primary size={}\n
             format fs=fat32 quick label=OSWORLDBOOT\n\
             assign\n\
             create partition primary\n\
             set id=\"0FC63DAF-8483-4772-8E79-3D69D8477DE4\"\n",
            disk_index, target_drive, shrink_mb, boot_mb
        );

        // Retry diskpart up to 3 times (temporary disk locks can cause failures)
        let mut diskpart_result = Err(InstallerError::SystemCheckFailed(
            "No attempts made".to_string(),
        ));
        for attempt in 1..=3 {
            diskpart_result = run_diskpart_script(&diskpart_script);
            if diskpart_result.is_ok() {
                break;
            }
            debug_log(&format!(
                "prepare_staging: diskpart attempt {} failed, retrying...",
                attempt
            ));
            if attempt < 3 {
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
        }

        debug_log(&format!(
            "prepare_staging: diskpart_result = {}",
            diskpart_result.is_ok()
        ));
        if let Err(ref e) = diskpart_result {
            let _ = cleanup_staging("OSWORLD".to_string());
            return Err(InstallerError::InstallationError(format!(
                "Partitioning failed after 3 attempts and rollback was attempted. Error: {}",
                e
            )));
        }

        write_install_state("prepare_partitioned", serde_json::Map::new());
        debug_log("prepare_staging: after write_install_state prepare_partitioned");

        // Disk space verification: ensure target drive still has >= 15% free
        // (skipped in test mode because tiny test partitions on small drives
        // would otherwise fail this heuristic.)
        if !is_test_mode() {
            let free_after_gb = get_disk_free_space(&target_drive).unwrap_or(0);

            let total_gb = if total_size_mb > 0 {
                total_size_mb / 1024
            } else {
                free_after_gb + linux_size_gb + 2
            };
            let free_percent = if total_gb > 0 {
                (free_after_gb * 100) / total_gb
            } else {
                0
            };
            if free_percent < 15 {
                let _ = cleanup_staging("OSWORLD".to_string());
                return Err(InstallerError::SystemCheckFailed(format!(
                    "{}: drive free space is too low after shrink ({}%). At least 15% is required.",
                    target_drive, free_percent
                )));
            }
        }

        // Locate created partitions
        let boot_letter = find_volume_by_label("OSWORLDBOOT").ok_or_else(|| {
            InstallerError::SystemCheckFailed("Could not locate created boot partition".to_string())
        })?;

        let linux_part_num = find_linux_partition_number(disk_index).ok_or_else(|| {
            InstallerError::SystemCheckFailed(
                "Could not locate created Linux partition".to_string(),
            )
        })?;

        let osworld_part_num = find_partition_number_by_letter(&boot_letter)?;

        // Update state: partitioning complete
        let updated_state = StagingState {
            timestamp: initial_state.timestamp.clone(),
            disk_index,
            target_drive_letter: None,
            original_target_drive_size_mb: None,
            efi_entries_before: initial_state.efi_entries_before.clone(),
            osworldboot_partition_number: Some(osworld_part_num),
            linux_partition_number: Some(linux_part_num),
            osworldboot_letter: Some(boot_letter.clone()),
            stage_completed: "partition".to_string(),
        };
        save_staging_state(&updated_state)?;

        // --- Secure Boot shim/MOK staging ---
        // If Secure Boot is enabled and we're using the MOK enrollment strategy,
        // download shim-signed binaries and generate a one-time MOK keypair
        // on the OSWORLDBOOT partition so the Live ISO installer can sign
        // rEFInd + the kernel and enroll the key via MokManager.
        //
        // Secure Boot chain on the installed system:
        //   Firmware â†’ shim (Microsoft-signed) â†’ signed rEFInd â†’ signed kernel
        if config.secure_boot_enabled == Some(true)
            && config.secure_boot_strategy.as_deref() == Some("mok_enrollment")
        {
            stage_secure_boot_files(&boot_letter)?;
        }

        write_install_state("prepare_complete", serde_json::Map::new());

        Ok(StagingInfo {
            boot_partition_letter: boot_letter,
            linux_partition_number: linux_part_num,
        })
    }

    #[cfg(not(windows))]
    {
        let _ = (config, confirmation);
        Err(InstallerError::SystemCheckFailed(
            "Staging is only supported on Windows".to_string(),
        ))
    }
}

/// Download Arch Linux ISO to the staging drive and write install-config.json.
#[tauri::command]
async fn download_and_stage_iso(
    target_drive_letter: String,
    config: InstallConfig,
    app: AppHandle,
) -> Result<DownloadProgress> {
    #[cfg(windows)]
    {
        write_install_state("download_start", serde_json::Map::new());
        debug_log("download_and_stage_iso: start");

        let drive = target_drive_letter.trim_end_matches(':');
        let iso_path = format!("{}:\\arch.iso", drive);
        let config_path = format!("{}:\\install-config.json", drive);

        // Write config first
        let config_json = serde_json::to_string_pretty(&config)
            .map_err(|e| InstallerError::Unknown(format!("Failed to serialize config: {}", e)))?;
        debug_log(&format!(
            "download_and_stage_iso: writing config to {}",
            config_path
        ));
        tokio::fs::write(&config_path, config_json)
            .await
            .map_err(|e| {
                InstallerError::InstallationError(format!("Failed to write config: {}", e))
            })?;

        // Download ISO with progress
        let url = iso_url();
        debug_log(&format!(
            "download_and_stage_iso: starting download from {} to {}",
            url, iso_path
        ));
        let result = match download_file_with_progress(url, &iso_path, &app).await {
            Ok(r) => r,
            Err(e) => {
                debug_log(&format!(
                    "download_and_stage_iso: primary download failed ({}), trying fallback",
                    e
                ));
                if url != FALLBACK_ISO_URL {
                    download_file_with_progress(FALLBACK_ISO_URL, &iso_path, &app).await?
                } else {
                    return Err(e);
                }
            }
        };
        debug_log("download_and_stage_iso: download complete");

        // Verify file size (> 500 MB)
        let metadata = tokio::fs::metadata(&iso_path).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to verify ISO: {}", e))
        })?;
        let size_mb = metadata.len() / (1024 * 1024);
        if size_mb < 500 {
            return Err(InstallerError::InstallationError(format!(
                "Downloaded ISO is too small ({} MB)",
                size_mb
            )));
        }

        // Extract kernel and initrd from the ISO so rEFInd can boot it directly
        let iso_label = extract_arch_iso_files(&iso_path, drive).await?;

        // Save ISO label for refind.conf generation
        let label_path = format!("{}:\\iso-label.txt", drive);
        tokio::fs::write(&label_path, &iso_label)
            .await
            .map_err(|e| {
                InstallerError::InstallationError(format!("Failed to write ISO label: {}", e))
            })?;

        // Update staging state: download complete
        if let Some(mut state) = load_staging_state() {
            state.stage_completed = "download".to_string();
            let _ = save_staging_state(&state);
        }

        write_install_state("download_complete", serde_json::Map::new());

        Ok(result)
    }
    #[cfg(not(windows))]
    {
        let _ = (target_drive_letter, config, app);
        Err(InstallerError::SystemCheckFailed(
            "ISO staging is only supported on Windows".to_string(),
        ))
    }
}

/// Download and install rEFInd bootloader to the ESP.
#[tauri::command]
async fn install_refind() -> Result<()> {
    #[cfg(windows)]
    {
        write_install_state("bootloader_start", serde_json::Map::new());

        if is_test_mode() {
            write_install_state("bootloader_complete", serde_json::Map::new());
            return Ok(());
        }

        let temp_dir = std::env::temp_dir().join("osworld-refind");
        let zip_path = temp_dir.join("refind.zip");
        tokio::fs::create_dir_all(&temp_dir).await.map_err(|e| {
            InstallerError::InstallationError(format!("Failed to create temp dir: {}", e))
        })?;

        // Try bundled rEFInd first, fall back to download
        let bundled = find_bundled_refind_zip();
        if let Some(bundled_path) = bundled {
            debug_log(&format!("Using bundled rEFInd from: {:?}", bundled_path));
            tokio::fs::copy(&bundled_path, &zip_path)
                .await
                .map_err(|e| {
                    InstallerError::InstallationError(format!(
                        "Failed to copy bundled rEFInd: {}",
                        e
                    ))
                })?;
        } else {
            debug_log("Bundled rEFInd not found, falling back to download");
            let refind_url =
                "https://downloads.sourceforge.net/project/refind/0.14.2/refind-bin-0.14.2.zip";
            download_file_simple(refind_url, &zip_path).await?;
        }

        // Extract zip
        let extract_dir = temp_dir.join("extracted");
        extract_zip(&zip_path, &extract_dir)?;

        // Find refind directory inside extraction
        let refind_dir = find_refind_dir(&extract_dir)?;

        // Assign temporary letter to ESP
        let esp_letter = assign_esp_letter()?;
        let esp_path = format!("{}:\\", esp_letter);

        // Create EFI directories
        let refind_efi_path = format!("{}EFI\\refind\\", esp_path);
        let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);
        std::fs::create_dir_all(&refind_efi_path).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to create EFI dir: {}", e))
        })?;
        std::fs::create_dir_all(&refind_boot_path).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to create BOOT dir: {}", e))
        })?;

        // Copy rEFInd EFI files
        let refind_efi_src = refind_dir.join("refind_x64.efi");
        std::fs::copy(
            &refind_efi_src,
            format!("{}refind_x64.efi", refind_efi_path),
        )
        .map_err(|e| {
            InstallerError::InstallationError(format!("Failed to copy refind_x64.efi: {}", e))
        })?;
        std::fs::copy(&refind_efi_src, format!("{}bootx64.efi", refind_boot_path)).map_err(
            |e| {
                InstallerError::InstallationError(format!(
                    "Failed to copy fallback bootx64.efi: {}",
                    e
                ))
            },
        )?;

        // Copy icons directory if present
        let icons_src = refind_dir.join("icons");
        if icons_src.exists() {
            let icons_dst = format!("{}icons\\", refind_efi_path);
            copy_dir_all(&icons_src, &icons_dst)?;
        }

        // Read ISO label from boot partition for archisolabel parameter
        let iso_label = find_volume_by_label("OSWORLDBOOT")
            .and_then(|letter| {
                let path = format!("{}\\iso-label.txt", letter.trim_end_matches(':'));
                std::fs::read_to_string(&path).ok()
            })
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "ARCH_202501".to_string());

        // Create refind.conf with proper EFI-style forward-slash paths
        // Includes both Installer and Recovery entries.
        // default_selection + use_nvram false guarantees the installer entry is
        // highlighted on the next boot even if rEFInd has seen another OS before.
        let config_content = format!(
            r#"timeout 10
use_nvram false
default_selection "OSWorld Installer"

menuentry "OSWorld Installer" {{
    icon \EFI\refind\icons\os_linux.png
    volume OSWORLDBOOT
    loader /arch/boot/x86_64/vmlinuz-linux
    initrd /arch/boot/x86_64/archiso.img
    options "img_dev=/dev/disk/by-label/OSWORLDBOOT img_loop=/arch.iso archisobasedir=arch archisolabel={}"
}}

menuentry "AltOS Recovery" {{
    icon \EFI\refind\icons\os_rescue.png
    volume OSWORLDBOOT
    loader /arch/boot/x86_64/vmlinuz-linux
    initrd /arch/boot/x86_64/archiso.img
    options "img_dev=/dev/disk/by-label/OSWORLDBOOT img_loop=/arch.iso archisobasedir=arch archisolabel={} rescue_mode=1"
}}
"#,
            iso_label, iso_label
        );
        std::fs::write(format!("{}refind.conf", refind_efi_path), config_content).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write refind.conf: {}", e))
        })?;

        // --- Secure Boot: install shim as the primary bootloader ---
        // If shim files were staged on OSWORLDBOOT, copy them to the ESP and
        // register shim (not refind directly) as the BCD boot entry.
        // Chain: Firmware â†’ shim â†’ rEFInd â†’ kernel
        let secure_boot_staged = find_volume_by_label("OSWORLDBOOT")
            .map(|letter| {
                let flag = format!(
                    "{}\\secureboot\\enrollment-needed",
                    letter.trim_end_matches(':')
                );
                std::path::Path::new(&flag).exists()
            })
            .unwrap_or(false);

        if secure_boot_staged {
            install_shim_to_esp(&esp_letter, &refind_boot_path)?;
            add_secure_boot_bcd_entry(&esp_letter)?;
        } else {
            // Standard (non-Secure-Boot) BCD entry
            add_refind_bcd_entry(&esp_letter)?;
        }

        // Remove temporary ESP letter
        remove_esp_letter(&esp_letter)?;

        // Update staging state: rEFInd installed
        if let Some(mut state) = load_staging_state() {
            state.stage_completed = "refind".to_string();
            let _ = save_staging_state(&state);
        }

        write_install_state("bootloader_complete", serde_json::Map::new());

        Ok(())
    }
    #[cfg(not(windows))]
    {
        Err(InstallerError::SystemCheckFailed(
            "rEFInd installation is only supported on Windows".to_string(),
        ))
    }
}

/// Reboot the computer into the installer. In test mode, writes state and returns
/// without actually rebooting.
#[tauri::command]
fn reboot_to_installer() -> Result<()> {
    if TEST_MODE_ENABLED.load(Ordering::Relaxed) {
        let _ = write_test_state(
            "C:\\\\altos-test-state.json".to_string(),
            serde_json::json!({
                "screen": "progress",
                "stage": "ready_to_reboot",
                "testMode": true,
                "timestamp": std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64
            })
            .to_string(),
        );
        return Ok(());
    }

    #[cfg(windows)]
    {
        std::process::Command::new("shutdown")
            .args(&["/r", "/t", "5", "/c", "Rebooting to OSWorld Installer..."])
            .spawn()
            .map_err(|e| {
                InstallerError::SystemCheckFailed(format!("Failed to initiate reboot: {}", e))
            })?;
        Ok(())
    }
    #[cfg(not(windows))]
    {
        Err(InstallerError::SystemCheckFailed(
            "Reboot is only supported on Windows".to_string(),
        ))
    }
}

/// Enable or disable backend test mode. When enabled, destructive final actions
/// (e.g. reboot) are intercepted and recorded instead of executed.
#[tauri::command]
fn set_test_mode(enabled: bool) {
    #[cfg(debug_assertions)]
    {
        TEST_MODE_ENABLED.store(enabled, Ordering::Relaxed);
    }
    let _ = enabled;
}

#[allow(dead_code)]
fn debug_log(msg: &str) {
    use std::io::Write;
    let msg = format!(
        "{}: {}\n",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
        msg
    );
    let _ = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("C:\\altos-debug.log")
        .and_then(|mut f| f.write_all(msg.as_bytes()));
}

#[allow(dead_code)]
fn write_install_state(stage: &str, extra: serde_json::Map<String, serde_json::Value>) {
    let _ = write_test_state("C:\\\\altos-test-state.json".to_string(), {
        let mut obj = serde_json::Map::new();
        obj.insert(
            "screen".to_string(),
            serde_json::Value::String("progress".to_string()),
        );
        obj.insert(
            "stage".to_string(),
            serde_json::Value::String(stage.to_string()),
        );
        obj.insert(
            "timestamp".to_string(),
            serde_json::Value::Number(serde_json::Number::from(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64,
            )),
        );
        for (k, v) in extra {
            obj.insert(k, v);
        }
        serde_json::Value::Object(obj).to_string()
    });
}

/// Write test state JSON to disk for automated UI testing (appends to array)
#[tauri::command]
fn write_test_state(path: String, json: String) -> Result<()> {
    let mut entries: Vec<serde_json::Value> = Vec::new();
    if let Ok(existing) = std::fs::read_to_string(&path) {
        if let Ok(arr) = serde_json::from_str::<Vec<serde_json::Value>>(&existing) {
            entries = arr;
        } else if let Ok(obj) = serde_json::from_str::<serde_json::Value>(&existing) {
            entries = vec![obj];
        }
    }
    let new_entry: serde_json::Value = serde_json::from_str(&json)
        .map_err(|e| InstallerError::Unknown(format!("Invalid test state JSON: {}", e)))?;
    entries.push(new_entry);
    let out = serde_json::to_string_pretty(&entries)
        .map_err(|e| InstallerError::Unknown(format!("Failed to serialize test state: {}", e)))?;
    std::fs::write(&path, out)
        .map_err(|e| InstallerError::Unknown(format!("Failed to write test state: {}", e)))?;
    Ok(())
}

/// Mark the post-install onboarding as seen so it doesn't show again.
#[tauri::command]
fn mark_post_install_seen() -> Result<()> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let path = std::path::Path::new(&home).join(".config/altos/post-install-seen");
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    std::fs::write(&path, "1").map_err(|e| {
        InstallerError::Unknown(format!("Failed to write post-install marker: {}", e))
    })?;
    Ok(())
}

/// Set rEFInd default boot entry (AltOS or Windows).
#[tauri::command]
fn set_refind_default(enabled: bool) -> Result<()> {
    #[cfg(not(windows))]
    {
        let conf_path = std::path::Path::new("/boot/efi/EFI/refind/refind.conf");
        if !conf_path.exists() {
            return Ok(());
        }
        let content = std::fs::read_to_string(conf_path).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to read refind.conf: {}", e))
        })?;

        let target = if enabled { "\"AltOS\"" } else { "\"Windows\"" };
        let new_line = format!("default_selection {}", target);

        let new_content = if content.contains("default_selection") {
            content
                .lines()
                .map(|line| {
                    if line.trim().starts_with("default_selection") {
                        &new_line
                    } else {
                        line
                    }
                })
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            format!("{}\n{}", new_line, content)
        };

        std::fs::write(conf_path, new_content).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to write refind.conf: {}", e))
        })?;
    }
    #[cfg(windows)]
    {
        let _ = enabled;
    }
    Ok(())
}

// ==================== Secure Boot Helpers ====================

/// Stage shim-signed binaries and a one-time MOK keypair onto the
/// OSWORLDBOOT partition so the Live ISO installer can sign rEFInd
/// and the kernel, then enroll the key via MokManager.
#[cfg(windows)]
fn stage_secure_boot_files(boot_letter: &str) -> Result<()> {
    let drive = boot_letter.trim_end_matches(':');
    let sb_dir = format!("{}:\\secureboot", drive);
    std::fs::create_dir_all(&sb_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create secureboot dir: {}", e))
    })?;

    // 1) Download shim-signed EFI binaries (Microsoft-signed)
    download_shim_files(&sb_dir)?;

    // 2) Generate a one-time MOK keypair with OpenSSL
    generate_mok_keypair(&sb_dir)?;

    // 3) Write the enrollment-needed flag so the Live ISO knows to run
    //    the MOK enrollment flow after installing the system.
    let flag_path = format!("{}:\\secureboot\\enrollment-needed", drive);
    std::fs::write(&flag_path, "1").map_err(|e| {
        InstallerError::InstallationError(format!("Failed to write enrollment flag: {}", e))
    })?;

    Ok(())
}

/// Download Microsoft-signed shim binaries.
/// In production these should be bundled under resources/shim/ or
/// self-hosted.  The URLs below are placeholders â€” replace them with
/// your own trusted mirrors.
#[cfg(windows)]
fn download_shim_files(output_dir: &str) -> Result<()> {
    // Try bundled files first (preferred â€” no network dependency)
    if let Ok(exe_path) = std::env::current_exe() {
        let bundled_dir = exe_path
            .parent()
            .unwrap_or(std::path::Path::new("."))
            .join("resources/shim");
        let files = ["shimx64.efi", "mmx64.efi", "fbx64.efi"];
        let all_present = files.iter().all(|f| bundled_dir.join(f).exists());
        if all_present {
            for f in &files {
                let src = bundled_dir.join(f);
                let dst = std::path::Path::new(output_dir).join(f);
                std::fs::copy(&src, &dst).map_err(|e| {
                    InstallerError::InstallationError(format!(
                        "Failed to copy bundled shim file {}: {}",
                        f, e
                    ))
                })?;
            }
            return Ok(());
        }
    }

    // Fallback: download from known URLs.
    // IMPORTANT: Replace these placeholder URLs with actual hosted binaries
    // before shipping.  The binaries must be the Microsoft-signed versions
    // from a major distro (e.g. Ubuntu shim-signed or Fedora shim).
    let downloads = vec![
        (
            "shimx64.efi",
            "https://github.com/osworld-installer/shim-binaries/raw/main/shimx64.efi",
        ),
        (
            "mmx64.efi",
            "https://github.com/osworld-installer/shim-binaries/raw/main/mmx64.efi",
        ),
        (
            "fbx64.efi",
            "https://github.com/osworld-installer/shim-binaries/raw/main/fbx64.efi",
        ),
    ];

    for (filename, url) in downloads {
        let dst = std::path::Path::new(output_dir).join(filename);
        // Use a simple blocking download via PowerShell / curl
        let output = std::process::Command::new("powershell")
            .args(&[
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                &format!(
                    "Invoke-WebRequest -Uri '{}' -OutFile '{}' -UseBasicParsing",
                    url,
                    dst.to_string_lossy().replace("\\", "\\\\")
                ),
            ])
            .output()
            .map_err(|e| {
                InstallerError::InstallationError(format!("Failed to download {}: {}", filename, e))
            })?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(InstallerError::InstallationError(format!(
                "Download of {} failed: {}",
                filename, stderr
            )));
        }
    }

    Ok(())
}

/// Generate a one-time MOK (Machine Owner Key) keypair using OpenSSL.
/// The private key (MOK.key) and certificate (MOK.crt / MOK.cer) are
/// written to the staging partition.  The Live ISO installer uses them
/// to sign rEFInd and the kernel, then enrolls the certificate via
/// mokutil so the firmware trusts the signatures.
#[cfg(windows)]
fn generate_mok_keypair(output_dir: &str) -> Result<()> {
    // Verify openssl is available
    let check = std::process::Command::new("powershell")
        .args(&[
            "-NoProfile",
            "-Command",
            "Get-Command openssl -ErrorAction SilentlyContinue",
        ])
        .output()
        .map_err(|e| {
            InstallerError::InstallationError(format!("Failed to check for openssl: {}", e))
        })?;

    if !check.status.success() {
        return Err(InstallerError::InstallationError(
            "OpenSSL is required for Secure Boot MOK generation but was not found on this system. \
             Please install OpenSSL or disable Secure Boot in BIOS."
                .to_string(),
        ));
    }

    let key_path = std::path::Path::new(output_dir).join("MOK.key");
    let crt_path = std::path::Path::new(output_dir).join("MOK.crt");
    let cer_path = std::path::Path::new(output_dir).join("MOK.cer");

    // Generate self-signed certificate + private key
    let gen_cmd = format!(
        "openssl req -new -x509 -newkey rsa:2048 -keyout '{}' -out '{}' -nodes -days 3650 -subj \"/CN=AltOS Secure Boot/\"",
        key_path.to_string_lossy().replace("\\", "\\\\"),
        crt_path.to_string_lossy().replace("\\", "\\\\")
    );

    let output = std::process::Command::new("powershell")
        .args(&[
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            &gen_cmd,
        ])
        .output()
        .map_err(|e| {
            InstallerError::InstallationError(format!("OpenSSL key generation failed: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(InstallerError::InstallationError(format!(
            "Failed to generate MOK keypair: {}",
            stderr
        )));
    }

    // Convert CRT to DER (CER) for mokutil enrollment
    let der_cmd = format!(
        "openssl x509 -in '{}' -out '{}' -outform DER",
        crt_path.to_string_lossy().replace("\\", "\\\\"),
        cer_path.to_string_lossy().replace("\\", "\\\\")
    );

    let output = std::process::Command::new("powershell")
        .args(&[
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            &der_cmd,
        ])
        .output()
        .map_err(|e| {
            InstallerError::InstallationError(format!("OpenSSL DER conversion failed: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(InstallerError::InstallationError(format!(
            "Failed to convert MOK certificate to DER: {}",
            stderr
        )));
    }

    Ok(())
}

/// Copy shim binaries from OSWORLDBOOT to the ESP fallback directory.
/// bootx64.efi is replaced with shimx64.efi so the firmware loads shim
/// first.  mmx64.efi and fbx64.efi are copied alongside it.
#[cfg(windows)]
fn install_shim_to_esp(esp_letter: &str, boot_path: &str) -> Result<()> {
    let boot_drive = find_volume_by_label("OSWORLDBOOT").ok_or_else(|| {
        InstallerError::InstallationError(
            "Could not find OSWORLDBOOT partition for shim files".to_string(),
        )
    })?;
    let staging_drive = boot_drive.trim_end_matches(':');

    // Copy shim, MokManager, and fallback binaries to EFI/BOOT
    let files = [
        ("shimx64.efi", "bootx64.efi"),
        ("mmx64.efi", "mmx64.efi"),
        ("fbx64.efi", "fbx64.efi"),
    ];
    for (src_name, dst_name) in &files {
        let src = format!("{}:\\secureboot\\{}", staging_drive, src_name);
        let dst = format!("{}{}", boot_path, dst_name);
        std::fs::copy(&src, &dst).map_err(|e| {
            InstallerError::InstallationError(format!("Failed to copy {} to ESP: {}", src_name, e))
        })?;
    }

    Ok(())
}

/// Add a BCD firmware entry that points to shim (not directly to rEFInd).
/// When Secure Boot is enabled, the chain is:
///   Firmware â†’ shim (Microsoft-signed) â†’ signed rEFInd â†’ signed kernel
#[cfg(windows)]
fn add_secure_boot_bcd_entry(esp_letter: &str) -> Result<()> {
    let l = esp_letter.trim_end_matches(':');

    let output = std::process::Command::new("bcdedit")
        .args(&[
            "/copy",
            "{current}",
            "/d",
            "OSWorld Installer (Secure Boot)",
        ])
        .output()
        .map_err(|e| InstallerError::InstallationError(format!("bcdedit failed: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let guid = stdout
        .split('{')
        .nth(1)
        .and_then(|s| s.split('}').next())
        .map(|s| format!("{{{}}}", s))
        .ok_or_else(|| {
            InstallerError::InstallationError("Failed to parse bcdedit GUID".to_string())
        })?;

    let commands = vec![
        // Point to shim instead of refind directly
        format!("bcdedit /set {} path \\EFI\\BOOT\\shimx64.efi", guid),
        format!("bcdedit /set {} device partition={}:", guid, l),
        format!("bcdedit /displayorder {} /addfirst", guid),
        // One-time next boot so the installer starts automatically on restart.
        format!("bcdedit /bootsequence {} /addfirst", guid),
    ];

    for cmd in commands {
        let parts: Vec<&str> = cmd.split_whitespace().collect();
        let status = std::process::Command::new(parts[0])
            .args(&parts[1..])
            .status()
            .map_err(|e| {
                InstallerError::InstallationError(format!("bcdedit command failed: {}", e))
            })?;

        if !status.success() {
            return Err(InstallerError::InstallationError(format!(
                "bcdedit command failed: {}",
                cmd
            )));
        }
    }

    Ok(())
}

// ==================== Helper Functions ====================

#[cfg(windows)]
fn to_wide(s: &str) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    std::ffi::OsStr::new(s)
        .encode_wide()
        .chain(Some(0))
        .collect()
}

#[cfg(windows)]
fn reg_query_string(hkey: *mut std::ffi::c_void, subkey: &str, value: &str) -> Option<String> {
    use windows_sys::Win32::System::Registry::{
        RegCloseKey, RegOpenKeyExW, RegQueryValueExW, KEY_READ,
    };

    let subkey_wide = to_wide(subkey);
    let value_wide = to_wide(value);
    let mut h: *mut std::ffi::c_void = std::ptr::null_mut();

    let status = unsafe { RegOpenKeyExW(hkey, subkey_wide.as_ptr(), 0, KEY_READ, &mut h) };

    if status != 0 {
        return None;
    }

    let mut buf_size: u32 = 0;

    unsafe {
        RegQueryValueExW(
            h,
            value_wide.as_ptr(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut buf_size,
        );
    }

    if buf_size == 0 || buf_size > 4096 {
        unsafe { RegCloseKey(h) };
        return None;
    }

    let mut buf = vec![0u8; buf_size as usize];
    let status = unsafe {
        RegQueryValueExW(
            h,
            value_wide.as_ptr(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            buf.as_mut_ptr(),
            &mut buf_size,
        )
    };

    unsafe { RegCloseKey(h) };

    if status != 0 {
        return None;
    }

    let u16_slice =
        unsafe { std::slice::from_raw_parts(buf.as_ptr() as *const u16, buf.len() / 2) };

    let u16_vec: Vec<u16> = u16_slice.iter().copied().take_while(|&c| c != 0).collect();
    String::from_utf16(&u16_vec).ok()
}

#[cfg(windows)]
fn reg_query_dword(hkey: *mut std::ffi::c_void, subkey: &str, value: &str) -> Option<u32> {
    use windows_sys::Win32::System::Registry::{
        RegCloseKey, RegOpenKeyExW, RegQueryValueExW, KEY_READ,
    };

    let subkey_wide = to_wide(subkey);
    let value_wide = to_wide(value);
    let mut h: *mut std::ffi::c_void = std::ptr::null_mut();

    let status = unsafe { RegOpenKeyExW(hkey, subkey_wide.as_ptr(), 0, KEY_READ, &mut h) };

    if status != 0 {
        return None;
    }

    let mut data: u32 = 0;
    let mut data_size: u32 = std::mem::size_of::<u32>() as u32;
    let mut data_type: u32 = 0;

    let status = unsafe {
        RegQueryValueExW(
            h,
            value_wide.as_ptr(),
            std::ptr::null_mut(),
            &mut data_type,
            &mut data as *mut u32 as *mut u8,
            &mut data_size,
        )
    };

    unsafe { RegCloseKey(h) };

    if status != 0 || data_type != 4 {
        // 4 = REG_DWORD
        return None;
    }

    Some(data)
}

#[cfg(all(windows, not(feature = "test-mocks")))]
async fn detect_windows_version() -> Result<String> {
    let product_name = reg_query_string(
        windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
        r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
        "ProductName",
    )
    .unwrap_or_else(|| "Windows".to_string());

    let display_version = reg_query_string(
        windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
        r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
        "DisplayVersion",
    );

    let release_id = reg_query_string(
        windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
        r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
        "ReleaseId",
    );

    let version = match (display_version, release_id) {
        (Some(dv), _) => format!("{} ({})", product_name.trim(), dv.trim()),
        (None, Some(ri)) => format!("{} ({})", product_name.trim(), ri.trim()),
        _ => product_name.trim().to_string(),
    };

    Ok(version)
}

#[cfg(any(not(windows), feature = "test-mocks"))]
async fn detect_windows_version() -> Result<String> {
    Ok(std::env::var("MOCK_WINDOWS_VERSION")
        .unwrap_or_else(|_| "Windows 11 Pro (23H2)".to_string()))
}

#[cfg(all(windows, not(feature = "test-mocks")))]
fn get_disk_free_space(drive_letter: &str) -> Option<u64> {
    use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

    let path = to_wide(&format!("{}:\\", drive_letter));
    let mut free_bytes: u64 = 0;

    let result = unsafe {
        GetDiskFreeSpaceExW(
            path.as_ptr(),
            &mut free_bytes,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    };

    if result == 0 {
        return None;
    }

    Some(free_bytes / (1024 * 1024 * 1024))
}

/// Extract drive letter from a selected_disk string like "Disk 1 (D:)"
#[allow(dead_code)]
fn extract_drive_letter(selected_disk: &str) -> Option<String> {
    selected_disk
        .split('(')
        .nth(1)?
        .split(')')
        .next()?
        .trim_end_matches(':')
        .chars()
        .next()
        .map(|c| c.to_string())
}

#[cfg(any(not(windows), feature = "test-mocks"))]
fn get_disk_free_space(_drive_letter: &str) -> Option<u64> {
    std::env::var("MOCK_FREE_SPACE_GB")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .or(Some(250))
}

#[cfg(all(windows, not(feature = "test-mocks")))]
fn check_secure_boot() -> Option<bool> {
    let val = reg_query_dword(
        windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE as *mut c_void,
        r"SYSTEM\CurrentControlSet\Control\SecureBoot\State",
        "UEFISecureBootEnabled",
    );
    Some(val.unwrap_or(0) != 0)
}

#[cfg(any(not(windows), feature = "test-mocks"))]
fn check_secure_boot() -> Option<bool> {
    std::env::var("MOCK_SECURE_BOOT").ok().map(|v| v == "true")
}

#[tauri::command]
fn suspend_bitlocker(drive_letter: String) -> Result<String> {
    #[cfg(windows)]
    {
        let drive = if drive_letter.ends_with(':') {
            drive_letter
        } else {
            format!("{}:", drive_letter)
        };
        let output = run_powershell(&format!("manage-bde -protectors -disable {}", drive))?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !output.status.success() {
            return Err(InstallerError::SystemCheckFailed(format!(
                "Failed to suspend BitLocker: {}",
                stderr
            )));
        }
        Ok(format!(
            "BitLocker suspended on {}. Output: {}",
            drive, stdout
        ))
    }
    #[cfg(not(windows))]
    {
        let _ = drive_letter;
        Err(InstallerError::SystemCheckFailed(
            "BitLocker suspension is only supported on Windows".to_string(),
        ))
    }
}

#[cfg(all(windows, not(feature = "test-mocks")))]
fn check_bitlocker() -> Option<bool> {
    use serde::Deserialize;
    use wmi::{COMLibrary, WMIConnection};

    #[derive(Deserialize, Debug)]
    struct Win32EncryptableVolume {
        #[serde(rename = "DriveLetter")]
        _drive_letter: String,
        #[serde(rename = "ProtectionStatus")]
        protection_status: u32,
    }

    let com = COMLibrary::new().ok()?;
    let wmi = WMIConnection::new(com).ok()?;

    let volumes: Vec<Win32EncryptableVolume> = wmi
        .raw_query("SELECT * FROM Win32_EncryptableVolume WHERE DriveLetter='C:'")
        .ok()?;

    if volumes.is_empty() {
        return Some(false);
    }

    // 0 = Unprotected, 1 = Protected, 2 = Unknown
    Some(volumes[0].protection_status == 1)
}

#[cfg(any(not(windows), feature = "test-mocks"))]
fn check_bitlocker() -> Option<bool> {
    std::env::var("MOCK_BITLOCKER").ok().map(|v| v == "true")
}

// ==================== Staging Helpers ====================

#[cfg(windows)]
fn run_powershell(command: &str) -> Result<std::process::Output> {
    let output = std::process::Command::new("powershell")
        .args(&[
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            command,
        ])
        .output()
        .map_err(|e| {
            InstallerError::SystemCheckFailed(format!("PowerShell execution failed: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(InstallerError::SystemCheckFailed(format!(
            "PowerShell error: {}",
            stderr
        )));
    }

    Ok(output)
}

#[cfg(windows)]
fn is_uefi() -> bool {
    let output = run_powershell(
        "if (Get-Partition | Where-Object { $_.Type -eq 'System' }) { Write-Output 'UEFI' } else { Write-Output 'BIOS' }"
    );
    match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim() == "UEFI",
        Err(_) => false,
    }
}

#[cfg(windows)]
fn get_system_disk_info() -> Result<(u32, bool)> {
    let output = run_powershell("(Get-Partition -DriveLetter C).DiskNumber")?;
    let disk_index = String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|_| {
            InstallerError::SystemCheckFailed("Could not parse system disk index".to_string())
        })?;

    let output = run_powershell(&format!("(Get-Disk -Number {}).PartitionStyle", disk_index))?;
    let style = String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|_| {
            InstallerError::SystemCheckFailed("Could not parse partition style".to_string())
        })?;

    Ok((disk_index, style == 1)) // 1 = GPT
}

#[cfg(windows)]
fn save_staging_state(state: &StagingState) -> Result<()> {
    let state_dir = std::path::Path::new(r"C:\ProgramData\OSWorld");
    let state_path = state_dir.join("staging-state.json");
    let log_dir = state_dir.join("logs");

    std::fs::create_dir_all(&state_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create state dir: {}", e))
    })?;
    std::fs::create_dir_all(&log_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create log dir: {}", e))
    })?;

    let json = serde_json::to_string_pretty(state).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to serialize state: {}", e))
    })?;

    std::fs::write(&state_path, json).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to write state file: {}", e))
    })?;

    Ok(())
}

#[cfg(windows)]
fn load_staging_state() -> Option<StagingState> {
    let state_path = std::path::Path::new(r"C:\ProgramData\OSWorld\staging-state.json");
    if !state_path.exists() {
        return None;
    }
    let content = std::fs::read_to_string(state_path).ok()?;
    serde_json::from_str(&content).ok()
}

#[cfg(windows)]
fn append_rollback_log(message: &str) {
    let log_dir = std::path::Path::new(r"C:\ProgramData\OSWorld\logs");
    let _ = std::fs::create_dir_all(log_dir);
    let log_path = log_dir.join("rollback.log");
    let now = std::time::SystemTime::now();
    let since_epoch = now
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let timestamp = format!(
        "{}.{:03}",
        since_epoch.as_secs(),
        since_epoch.subsec_millis()
    );
    let line = format!("[{}] {}\n", timestamp, message);
    let _ = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .and_then(|mut f| {
            use std::io::Write;
            f.write_all(line.as_bytes())
        });
}

#[cfg(windows)]
fn run_diskpart_script(script: &str) -> Result<String> {
    let temp_path = std::env::temp_dir().join(format!(
        "osworld_diskpart_{}_{}.txt",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
    ));
    std::fs::write(&temp_path, script).map_err(|e| {
        InstallerError::SystemCheckFailed(format!("Failed to write diskpart script: {}", e))
    })?;

    let output = std::process::Command::new("diskpart")
        .arg("/s")
        .arg(&temp_path)
        .output()
        .map_err(|e| {
            InstallerError::SystemCheckFailed(format!("diskpart execution failed: {}", e))
        })?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    let log = format!(
        "DISKPART SCRIPT:\n{}\n\nSTDOUT:\n{}\n\nSTDERR:\n{}\n\nEXIT: {}\n---\n",
        script,
        stdout,
        stderr,
        output.status.success()
    );
    let _ = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("C:\\altos-diskpart.log")
        .and_then(|mut f| std::io::Write::write_all(&mut f, log.as_bytes()));

    if !output.status.success()
        || stdout
            .to_lowercase()
            .contains("diskpart has encountered an error")
        || stderr.to_lowercase().contains("error")
    {
        return Err(InstallerError::SystemCheckFailed(format!(
            "diskpart failed. stdout: {}  stderr: {}",
            stdout, stderr
        )));
    }

    Ok(stdout)
}

#[cfg(windows)]
fn find_volume_by_label(label: &str) -> Option<String> {
    let output = run_powershell(&format!(
        "(Get-Volume -FileSystemLabel '{}').DriveLetter",
        label
    ))
    .ok()?;
    let letter = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if letter.is_empty() {
        None
    } else {
        Some(format!("{}:", letter))
    }
}

#[cfg(windows)]
fn find_linux_partition_number(disk_index: u32) -> Option<u32> {
    let output = run_powershell(&format!(
        "(Get-Partition -DiskNumber {} | Sort-Object PartitionNumber -Descending | Select-Object -First 1).PartitionNumber",
        disk_index
    )).ok()?;
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .ok()
}

#[cfg(windows)]
fn find_partition_number_by_letter(letter: &str) -> Result<u32> {
    let clean = letter.trim_end_matches(':');
    let output = run_powershell(&format!(
        "(Get-Partition | Where-Object {{ $_.DriveLetter -eq '{}' }}).PartitionNumber",
        clean
    ))?;
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|_| {
            InstallerError::SystemCheckFailed(format!(
                "Could not find partition number for drive {}",
                letter
            ))
        })
}

/// Mount the Arch ISO, extract kernel and initrd to the boot partition,
/// and return the ISO filesystem label.
#[cfg(windows)]
async fn extract_arch_iso_files(iso_path: &str, dest_drive: &str) -> Result<String> {
    // In test mode, skip actual ISO extraction and create dummy files
    // to avoid Mount-DiskImage hangs in non-interactive sessions
    if is_test_mode() {
        let drive = dest_drive.trim_end_matches(':');
        let dest_dir = format!("{}:\\arch\\boot\\x86_64", drive);
        let _ = std::fs::create_dir_all(&dest_dir);
        let _ = std::fs::write(format!("{}\\vmlinuz-linux", dest_dir), "TEST_VMLINUZ");
        let _ = std::fs::write(format!("{}\\archiso.img", dest_dir), "TEST_INITRD");
        return Ok("ARCH_TEST".to_string());
    }

    let drive = dest_drive.trim_end_matches(':');
    let dest_dir = format!("{}:\\arch\\boot\\x86_64", drive);

    tokio::fs::create_dir_all(&dest_dir).await.map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create arch boot dir: {}", e))
    })?;

    let ps_script = format!(
        "$iso = Mount-DiskImage -ImagePath '{}' -PassThru; \
         Start-Sleep -Milliseconds 800; \
         $vol = $iso | Get-Volume; \
         $letter = $vol.DriveLetter; \
         $label = $vol.FileSystemLabel; \
         Copy-Item -Path \"${{letter}}:\\arch\\boot\\x86_64\\vmlinuz-linux\" -Destination \"{}\\vmlinuz-linux\" -Force; \
         Copy-Item -Path \"${{letter}}:\\arch\\boot\\x86_64\\archiso.img\" -Destination \"{}\\archiso.img\" -Force; \
         Dismount-DiskImage -ImagePath '{}'; \
         Write-Output \"LABEL=$label\"",
        iso_path,
        dest_dir,
        dest_dir,
        iso_path
    );

    let output = run_powershell(&ps_script)?;
    let stdout = String::from_utf8_lossy(&output.stdout);

    let label = stdout
        .lines()
        .find(|l| l.starts_with("LABEL="))
        .and_then(|l| l.strip_prefix("LABEL="))
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "ARCH_202501".to_string());

    let vmlinuz_path = format!("{}\\vmlinuz-linux", dest_dir);
    let initrd_path = format!("{}\\archiso.img", dest_dir);

    if !std::path::Path::new(&vmlinuz_path).exists() {
        return Err(InstallerError::InstallationError(
            "Failed to extract vmlinuz-linux from ISO".to_string(),
        ));
    }
    if !std::path::Path::new(&initrd_path).exists() {
        return Err(InstallerError::InstallationError(
            "Failed to extract archiso.img from ISO".to_string(),
        ));
    }

    Ok(label)
}

#[cfg(windows)]
async fn download_file_with_progress(
    url: &str,
    path: &str,
    app: &AppHandle,
) -> Result<DownloadProgress> {
    use futures_util::StreamExt;

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(3600))
        .build()
        .map_err(|e| InstallerError::InstallationError(format!("HTTP client error: {}", e)))?;

    debug_log(&format!(
        "download_file_with_progress: sending request to {}",
        url
    ));
    let response = client.get(url).send().await.map_err(|e| {
        InstallerError::InstallationError(format!("Download request failed: {}", e))
    })?;

    let total_bytes = response.content_length().unwrap_or(0);
    let mut file = tokio::fs::File::create(path)
        .await
        .map_err(|e| InstallerError::InstallationError(format!("Failed to create file: {}", e)))?;

    debug_log(&format!(
        "download_file_with_progress: got response, content_length={:?}",
        response.content_length()
    ));
    let mut stream = response.bytes_stream();
    let mut downloaded: u64 = 0;
    let mut last_percent: u8 = 0;

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| {
            InstallerError::InstallationError(format!("Download stream error: {}", e))
        })?;
        tokio::io::AsyncWriteExt::write_all(&mut file, &chunk)
            .await
            .map_err(|e| {
                InstallerError::InstallationError(format!("Failed to write file: {}", e))
            })?;
        downloaded += chunk.len() as u64;

        if total_bytes > 0 {
            let percent = ((downloaded * 100) / total_bytes) as u8;
            if percent >= last_percent + 1 {
                last_percent = percent;
                let _ = app.emit(
                    "download-progress",
                    DownloadProgressEvent {
                        percent,
                        stage: "Downloading Arch Linux ISO...".to_string(),
                    },
                );
            }
        }
    }

    tokio::io::AsyncWriteExt::flush(&mut file)
        .await
        .map_err(|e| InstallerError::InstallationError(format!("Failed to flush file: {}", e)))?;

    Ok(DownloadProgress {
        percent: 100,
        stage: "Download complete".to_string(),
        bytes_downloaded: downloaded,
        total_bytes,
    })
}

#[cfg(windows)]
async fn download_file_simple(url: &str, path: &std::path::Path) -> Result<()> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| InstallerError::InstallationError(format!("HTTP client error: {}", e)))?;

    debug_log(&format!(
        "download_file_with_progress: sending request to {}",
        url
    ));
    let response = client.get(url).send().await.map_err(|e| {
        InstallerError::InstallationError(format!("Download request failed: {}", e))
    })?;

    let bytes = response
        .bytes()
        .await
        .map_err(|e| InstallerError::InstallationError(format!("Download failed: {}", e)))?;

    tokio::fs::write(path, &bytes)
        .await
        .map_err(|e| InstallerError::InstallationError(format!("Failed to write file: {}", e)))?;

    Ok(())
}

#[cfg(windows)]
fn extract_zip(zip_path: &std::path::Path, dest_dir: &std::path::Path) -> Result<()> {
    let file = std::fs::File::open(zip_path)
        .map_err(|e| InstallerError::InstallationError(format!("Failed to open zip: {}", e)))?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|e| InstallerError::InstallationError(format!("Failed to read zip: {}", e)))?;

    archive
        .extract(dest_dir)
        .map_err(|e| InstallerError::InstallationError(format!("Failed to extract zip: {}", e)))?;

    Ok(())
}

fn find_bundled_refind_zip() -> Option<std::path::PathBuf> {
    // Check multiple possible locations for the bundled rEFInd zip
    let candidates = [
        // Tauri bundled resources (next to exe)
        std::env::current_exe().ok().and_then(|p| {
            p.parent()
                .map(|d| d.join("resources").join("refind-bin-0.14.2.zip"))
        }),
        // Development build (repo root)
        Some(std::path::PathBuf::from(
            "src-tauri/resources/refind-bin-0.14.2.zip",
        )),
        // Relative to exe in target directory
        std::env::current_exe().ok().and_then(|p| {
            p.parent()
                .map(|d| d.join("..").join("resources").join("refind-bin-0.14.2.zip"))
        }),
    ];
    for candidate in candidates.iter().flatten() {
        if candidate.exists() {
            return Some(candidate.clone());
        }
    }
    None
}

#[allow(dead_code)]
fn find_bundled_refind() -> Option<std::path::PathBuf> {
    find_bundled_refind_zip()
}

#[cfg(windows)]
fn find_refind_dir(extract_dir: &std::path::Path) -> Result<std::path::PathBuf> {
    for entry in std::fs::read_dir(extract_dir).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to read extraction dir: {}", e))
    })? {
        let entry = entry
            .map_err(|e| InstallerError::InstallationError(format!("Dir entry error: {}", e)))?;
        let refind_subdir = entry.path().join("refind");
        if refind_subdir.exists() {
            return Ok(refind_subdir);
        }
    }
    Err(InstallerError::InstallationError(
        "Could not find refind directory in extracted archive".to_string(),
    ))
}

#[cfg(windows)]
fn assign_esp_letter() -> Result<String> {
    let output = run_powershell(
        "$letters = 83..90 | ForEach-Object { [char]$_ }; \
         $available = $letters | Where-Object { -not (Test-Path \"$($_):\") } | Select-Object -First 1; \
         if (-not $available) { throw 'No available drive letters' }; \
         $esp = Get-Partition | Where-Object { $_.Type -eq 'System' } | Select-Object -First 1; \
         if (-not $esp) { throw 'No ESP found' }; \
         Add-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath \"$($available):\" -ErrorAction Stop; \
         Write-Output $available"
    )?;

    let letter = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if letter.is_empty() {
        return Err(InstallerError::InstallationError(
            "Failed to assign ESP letter".to_string(),
        ));
    }
    Ok(format!("{}:", letter))
}

#[cfg(windows)]
fn remove_esp_letter(letter: &str) -> Result<()> {
    let l = letter.trim_end_matches(':');
    run_powershell(&format!(
        "$esp = Get-Partition | Where-Object {{ $_.AccessPaths -contains '{}:\' }} | Select-Object -First 1; \
         if ($esp) {{ Remove-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath '{}:\' -ErrorAction Stop }}",
        l, l
    ))?;
    Ok(())
}

#[cfg(windows)]
fn add_refind_bcd_entry(esp_letter: &str) -> Result<()> {
    let l = esp_letter.trim_end_matches(':');

    let output = std::process::Command::new("bcdedit")
        .args(&["/copy", "{current}", "/d", "OSWorld Installer (rEFInd)"])
        .output()
        .map_err(|e| InstallerError::InstallationError(format!("bcdedit failed: {}", e)))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let guid = stdout
        .split('{')
        .nth(1)
        .and_then(|s| s.split('}').next())
        .map(|s| format!("{{{}}}", s))
        .ok_or_else(|| {
            InstallerError::InstallationError("Failed to parse bcdedit GUID".to_string())
        })?;

    let commands = vec![
        format!("bcdedit /set {} path \\EFI\\refind\\refind_x64.efi", guid),
        format!("bcdedit /set {} device partition={}:", guid, l),
        format!("bcdedit /displayorder {} /addfirst", guid),
        // Set this entry as the one-time next boot so the firmware boots the
        // installer automatically on the next restart, without permanently
        // reordering the user's boot menu.
        format!("bcdedit /bootsequence {} /addfirst", guid),
    ];

    for cmd in commands {
        let parts: Vec<&str> = cmd.split_whitespace().collect();
        let status = std::process::Command::new(parts[0])
            .args(&parts[1..])
            .status()
            .map_err(|e| {
                InstallerError::InstallationError(format!("bcdedit command failed: {}", e))
            })?;

        if !status.success() {
            return Err(InstallerError::InstallationError(format!(
                "bcdedit command failed: {}",
                cmd
            )));
        }
    }

    Ok(())
}

#[cfg(windows)]
fn copy_dir_all(src: &std::path::Path, dst: &str) -> Result<()> {
    std::fs::create_dir_all(dst).map_err(|e| {
        InstallerError::InstallationError(format!("Failed to create dir {}: {}", dst, e))
    })?;

    for entry in std::fs::read_dir(src)
        .map_err(|e| InstallerError::InstallationError(format!("Failed to read dir: {}", e)))?
    {
        let entry = entry
            .map_err(|e| InstallerError::InstallationError(format!("Dir entry error: {}", e)))?;
        let src_path = entry.path();
        let file_name = entry.file_name();
        let dst_path = std::path::Path::new(dst).join(&file_name);

        if src_path.is_dir() {
            copy_dir_all(&src_path, dst_path.to_str().unwrap_or(""))?;
        } else {
            std::fs::copy(&src_path, &dst_path).map_err(|e| {
                InstallerError::InstallationError(format!("Failed to copy file: {}", e))
            })?;
        }
    }
    Ok(())
}

/// Write install-config.json to the staging drive without downloading ISO.
#[tauri::command]
async fn write_config(config: InstallConfig, drive: String) -> Result<()> {
    #[cfg(windows)]
    {
        let drive_clean = drive.trim_end_matches(':');
        let config_path = format!("{}:\\install-config.json", drive_clean);
        let config_json = serde_json::to_string_pretty(&config)
            .map_err(|e| InstallerError::Unknown(format!("Failed to serialize config: {}", e)))?;
        debug_log(&format!(
            "download_and_stage_iso: writing config to {}",
            config_path
        ));
        tokio::fs::write(&config_path, config_json)
            .await
            .map_err(|e| {
                InstallerError::InstallationError(format!("Failed to write config: {}", e))
            })?;
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = (config, drive);
        Err(InstallerError::SystemCheckFailed(
            "write_config is only supported on Windows".to_string(),
        ))
    }
}

/// Download Arch Linux ISO to the staging drive with progress events.
#[tauri::command]
async fn download_iso(drive: String, app: AppHandle) -> Result<DownloadProgress> {
    #[cfg(windows)]
    {
        let drive_clean = drive.trim_end_matches(':');
        let iso_path = format!("{}:\\arch.iso", drive_clean);
        let url = iso_url();

        // Resume check
        if let Ok(meta) = tokio::fs::metadata(&iso_path).await {
            let size_mb = meta.len() / (1024 * 1024);
            if size_mb > 500 {
                // Verify checksum even for resumed downloads
                match verify_iso_checksum(&iso_path).await {
                    Ok(true) => {
                        return Ok(DownloadProgress {
                            percent: 100,
                            stage: "ISO already downloaded and verified".to_string(),
                            bytes_downloaded: meta.len(),
                            total_bytes: meta.len(),
                        });
                    }
                    Ok(false) => {
                        // Checksum mismatch, re-download
                    }
                    Err(_) => {
                        // Can't verify, assume OK if large enough
                        return Ok(DownloadProgress {
                            percent: 100,
                            stage: "ISO already downloaded (checksum verification skipped)"
                                .to_string(),
                            bytes_downloaded: meta.len(),
                            total_bytes: meta.len(),
                        });
                    }
                }
            }
        }

        // Retry logic with exponential backoff, with fallback to Arch Linux ISO
        let mut last_error = None;
        let urls = if url != FALLBACK_ISO_URL {
            vec![url, FALLBACK_ISO_URL]
        } else {
            vec![url]
        };
        for current_url in urls {
            for attempt in 1..=3 {
                match download_file_with_progress(current_url, &iso_path, &app).await {
                    Ok(progress) => {
                        // Verify checksum after download
                        match verify_iso_checksum(&iso_path).await {
                            Ok(true) => return Ok(progress),
                            Ok(false) => {
                                return Err(InstallerError::InstallationError(
                                    "Downloaded ISO checksum does not match. File may be corrupted."
                                        .to_string(),
                                ));
                            }
                            Err(e) => {
                                // Checksum verification failed but download succeeded
                                return Ok(progress);
                            }
                        }
                    }
                    Err(e) => {
                        last_error = Some(e);
                        if attempt < 3 {
                            let backoff_secs = 2u64.pow(attempt - 1);
                            tokio::time::sleep(tokio::time::Duration::from_secs(backoff_secs))
                                .await;
                        }
                    }
                }
            }
        }

        Err(last_error.unwrap_or_else(|| {
            InstallerError::InstallationError("ISO download failed after 3 attempts".to_string())
        }))
    }
    #[cfg(not(windows))]
    {
        let _ = (drive, app);
        Err(InstallerError::SystemCheckFailed(
            "download_iso is only supported on Windows".to_string(),
        ))
    }
}

/// Verify that the installation staging is complete and valid.
#[tauri::command]
fn verify_installation() -> Result<VerificationStatus> {
    #[cfg(windows)]
    {
        let mut checks = Vec::new();

        // Check 1: OSWORLDBOOT partition exists and is FAT32
        let boot_check = match find_volume_by_label("OSWORLDBOOT") {
            Some(letter) => {
                let output = run_powershell(&format!(
                    "(Get-Volume -DriveLetter '{}').FileSystem",
                    letter.trim_end_matches(':')
                ));
                match output {
                    Ok(o) => {
                        let fs = String::from_utf8_lossy(&o.stdout).trim().to_lowercase();
                        if fs == "fat32" || fs == "fat" {
                            VerificationCheck {
                                name: "OSWORLDBOOT Partition".to_string(),
                                passed: true,
                                details: format!("Found at {} (FAT32)", letter),
                            }
                        } else {
                            VerificationCheck {
                                name: "OSWORLDBOOT Partition".to_string(),
                                passed: false,
                                details: format!(
                                    "Found at {} but filesystem is {} (expected FAT32)",
                                    letter, fs
                                ),
                            }
                        }
                    }
                    Err(e) => VerificationCheck {
                        name: "OSWORLDBOOT Partition".to_string(),
                        passed: false,
                        details: format!("Found partition but could not verify filesystem: {}", e),
                    },
                }
            }
            None => VerificationCheck {
                name: "OSWORLDBOOT Partition".to_string(),
                passed: false,
                details: "OSWORLDBOOT partition not found".to_string(),
            },
        };
        checks.push(boot_check);

        // Check 2: arch.iso exists and > 500MB
        let iso_check = if let Some(letter) = find_volume_by_label("OSWORLDBOOT") {
            let iso_path = format!("{}\\arch.iso", letter.trim_end_matches(':'));
            match std::fs::metadata(&iso_path) {
                Ok(meta) => {
                    let size_mb = meta.len() / (1024 * 1024);
                    if size_mb > 500 {
                        VerificationCheck {
                            name: "Arch ISO".to_string(),
                            passed: true,
                            details: format!("Found at {} ({} MB)", iso_path, size_mb),
                        }
                    } else {
                        VerificationCheck {
                            name: "Arch ISO".to_string(),
                            passed: false,
                            details: format!(
                                "Found at {} but too small ({} MB, expected > 500)",
                                iso_path, size_mb
                            ),
                        }
                    }
                }
                Err(_) => VerificationCheck {
                    name: "Arch ISO".to_string(),
                    passed: false,
                    details: format!("Not found at {}", iso_path),
                },
            }
        } else {
            VerificationCheck {
                name: "Arch ISO".to_string(),
                passed: false,
                details: "Cannot check ISO: OSWORLDBOOT partition not found".to_string(),
            }
        };
        checks.push(iso_check);

        // Check 3: install-config.json exists and is valid JSON
        let config_check = if let Some(letter) = find_volume_by_label("OSWORLDBOOT") {
            let config_path = format!("{}\\install-config.json", letter.trim_end_matches(':'));
            match std::fs::read_to_string(&config_path) {
                Ok(content) => match serde_json::from_str::<serde_json::Value>(&content) {
                    Ok(_) => VerificationCheck {
                        name: "Install Config".to_string(),
                        passed: true,
                        details: format!("Valid JSON at {}", config_path),
                    },
                    Err(e) => VerificationCheck {
                        name: "Install Config".to_string(),
                        passed: false,
                        details: format!("Invalid JSON at {}: {}", config_path, e),
                    },
                },
                Err(_) => VerificationCheck {
                    name: "Install Config".to_string(),
                    passed: false,
                    details: format!("Not found at {}", config_path),
                },
            }
        } else {
            VerificationCheck {
                name: "Install Config".to_string(),
                passed: false,
                details: "Cannot check config: OSWORLDBOOT partition not found".to_string(),
            }
        };
        checks.push(config_check);

        // Check 4: rEFInd files exist in EFI partition
        let refind_check = match assign_esp_letter() {
            Ok(esp_letter) => {
                let esp_path = format!("{}:\\", esp_letter);
                let refind_efi = format!("{}EFI\\refind\\refind_x64.efi", esp_path);
                let refind_conf = format!("{}EFI\\refind\\refind.conf", esp_path);
                let boot_efi = format!("{}EFI\\BOOT\\bootx64.efi", esp_path);

                let has_refind = std::path::Path::new(&refind_efi).exists();
                let has_conf = std::path::Path::new(&refind_conf).exists();
                let has_boot = std::path::Path::new(&boot_efi).exists();

                let _ = remove_esp_letter(&esp_letter);

                if has_refind && has_conf && has_boot {
                    VerificationCheck {
                        name: "rEFInd Bootloader".to_string(),
                        passed: true,
                        details: "All rEFInd files present in EFI partition".to_string(),
                    }
                } else {
                    let mut missing = Vec::new();
                    if !has_refind {
                        missing.push("refind_x64.efi");
                    }
                    if !has_conf {
                        missing.push("refind.conf");
                    }
                    if !has_boot {
                        missing.push("bootx64.efi");
                    }
                    VerificationCheck {
                        name: "rEFInd Bootloader".to_string(),
                        passed: false,
                        details: format!("Missing files: {}", missing.join(", ")),
                    }
                }
            }
            Err(e) => VerificationCheck {
                name: "rEFInd Bootloader".to_string(),
                passed: false,
                details: format!("Could not mount EFI partition: {}", e),
            },
        };
        checks.push(refind_check);

        let overall_pass = checks.iter().all(|c| c.passed);

        Ok(VerificationStatus {
            overall_pass,
            checks,
        })
    }
    #[cfg(not(windows))]
    {
        Ok(VerificationStatus {
            overall_pass: true,
            checks: vec![VerificationCheck {
                name: "Platform".to_string(),
                passed: true,
                details: "Verification is a no-op on non-Windows platforms".to_string(),
            }],
        })
    }
}

/// Detect if an AltOS installation exists on this system.
#[tauri::command]
fn detect_altos_installation() -> Result<bool> {
    #[cfg(windows)]
    {
        let has_osworld = find_volume_by_label("OSWORLDBOOT").is_some();
        let has_grub = run_powershell("bcdedit /enum | Select-String -Pattern 'OSWorld Installer'")
            .is_ok()
            && run_powershell("bcdedit /enum | Select-String -Pattern 'OSWorld Installer'")
                .map(|o| !String::from_utf8_lossy(&o.stdout).trim().is_empty())
                .unwrap_or(false);

        let has_refind = match assign_esp_letter() {
            Ok(esp) => {
                let exists =
                    std::path::Path::new(&format!("{}:\\EFI\\refind\\refind_x64.efi", esp))
                        .exists();
                let _ = remove_esp_letter(&esp);
                exists
            }
            Err(_) => false,
        };

        Ok(has_osworld || has_grub || has_refind)
    }
    #[cfg(not(windows))]
    {
        Ok(false)
    }
}

/// Remove AltOS partitions (OSWORLDBOOT and Linux partitions).
#[tauri::command]
fn remove_altos_partitions(confirmation: String, expand_target_drive: bool) -> Result<Vec<String>> {
    if confirmation != "REMOVE" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly REMOVE".to_string(),
        ));
    }

    #[cfg(windows)]
    {
        let mut actions = Vec::new();
        let disk_info = get_system_disk_info()?;
        let disk_index = disk_info.0;

        // Determine target drive for expansion (from staging state or default to C)
        let target_drive = load_staging_state()
            .and_then(|s| s.target_drive_letter)
            .unwrap_or_else(|| "C".to_string());

        // Remove Linux partition
        if let Some(linux_part) = find_linux_partition_number(disk_index) {
            match run_diskpart_script_with_timeout(
                &format!(
                    "select disk {}\nselect partition {}\ndelete partition override\n",
                    disk_index, linux_part
                ),
                60,
            ) {
                Ok(_) => actions.push(format!("Deleted Linux partition {}", linux_part)),
                Err(e) => actions.push(format!(
                    "Failed to delete Linux partition {}: {}",
                    linux_part, e
                )),
            }
        }

        // Remove OSWORLDBOOT partition
        if let Some(osworld_letter) = find_volume_by_label("OSWORLDBOOT") {
            let clean = osworld_letter.trim_end_matches(':');
            let output = run_powershell(&format!(
                "(Get-Partition | Where-Object {{ $_.DriveLetter -eq '{}' }}).PartitionNumber",
                clean
            ));
            if let Ok(o) = output {
                if let Ok(part_num) = String::from_utf8_lossy(&o.stdout).trim().parse::<u32>() {
                    match run_diskpart_script_with_timeout(
                        &format!(
                            "select disk {}\nselect partition {}\ndelete partition override\n",
                            disk_index, part_num
                        ),
                        60,
                    ) {
                        Ok(_) => {
                            actions.push(format!("Deleted OSWORLDBOOT partition {}", part_num))
                        }
                        Err(e) => actions.push(format!(
                            "Failed to delete OSWORLDBOOT partition {}: {}",
                            part_num, e
                        )),
                    }
                }
            }
        }

        // Expand target drive if requested
        if expand_target_drive {
            match run_diskpart_script_with_timeout(
                &format!(
                    "select disk {}\nselect volume {}\nextend\n",
                    disk_index, target_drive
                ),
                60,
            ) {
                Ok(_) => actions.push(format!("Expanded {}: drive to reclaim space", target_drive)),
                Err(e) => actions.push(format!("Failed to expand {}: drive: {}", target_drive, e)),
            }
        }

        Ok(actions)
    }
    #[cfg(not(windows))]
    {
        let _ = (confirmation, expand_target_drive);
        Err(InstallerError::SystemCheckFailed(
            "Partition removal is only supported on Windows".to_string(),
        ))
    }
}

/// Restore Windows Boot Manager as the default bootloader.
#[tauri::command]
fn restore_windows_bootloader() -> Result<String> {
    #[cfg(windows)]
    {
        // Remove OSWorld Installer BCD entries
        let output = std::process::Command::new("bcdedit")
            .args(&["/enum"])
            .output()
            .map_err(|e| {
                InstallerError::InstallationError(format!("bcdedit enum failed: {}", e))
            })?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if line.contains("OSWorld Installer") || line.contains("rEFInd") {
                if let Some(guid) = line.split('{').nth(1).and_then(|s| s.split('}').next()) {
                    let full_guid = format!("{{{}}}", guid);
                    let _ = std::process::Command::new("bcdedit")
                        .args(&["/delete", &full_guid, "/cleanup"])
                        .status();
                }
            }
        }

        // Restore Windows Boot Manager as default
        let result = run_powershell(
            "$bootmgr = bcdedit /enum firmware | Select-String -Pattern 'bootmgr' | Select-Object -First 1; \
             if ($bootmgr) { $guid = ($bootmgr -split '\\s+')[1]; bcdedit /displayorder $guid /addfirst | Out-Null; Write-Output 'OK' } else { Write-Output 'MISSING' }"
        );

        match result {
            Ok(o) if String::from_utf8_lossy(&o.stdout).trim() == "OK" => {
                Ok("Windows Boot Manager restored as default".to_string())
            }
            _ => {
                Err(InstallerError::InstallationError(
                    "Could not restore Windows Boot Manager automatically. You may need to use bcdedit manually.".to_string()
                ))
            }
        }
    }
    #[cfg(not(windows))]
    {
        Err(InstallerError::SystemCheckFailed(
            "Bootloader restoration is only supported on Windows".to_string(),
        ))
    }
}

/// Remove rEFInd files from the EFI System Partition.
#[tauri::command]
fn remove_refind_files() -> Result<String> {
    #[cfg(windows)]
    {
        let esp_letter = assign_esp_letter()?;
        let esp_path = format!("{}:\\", esp_letter);
        let refind_path = format!("{}EFI\\refind\\", esp_path);
        let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);
        let windows_boot_backup = format!("{}bootx64.efi.windows", refind_boot_path);
        let bootx64_path = format!("{}bootx64.efi", refind_boot_path);

        // Remove rEFInd directories
        let _ = std::fs::remove_dir_all(&refind_path);
        let _ = std::fs::remove_dir_all(&refind_boot_path);

        // Restore Windows bootloader from backup if it exists
        if std::path::Path::new(&windows_boot_backup).exists() {
            std::fs::create_dir_all(&refind_boot_path).map_err(|e| {
                InstallerError::InstallationError(format!("Failed to recreate BOOT dir: {}", e))
            })?;
            std::fs::copy(&windows_boot_backup, &bootx64_path).map_err(|e| {
                InstallerError::InstallationError(format!(
                    "Failed to restore Windows bootloader: {}",
                    e
                ))
            })?;
            let _ = std::fs::remove_file(&windows_boot_backup);
        }

        remove_esp_letter(&esp_letter)?;

        Ok("rEFInd files removed successfully".to_string())
    }
    #[cfg(not(windows))]
    {
        Err(InstallerError::SystemCheckFailed(
            "rEFInd removal is only supported on Windows".to_string(),
        ))
    }
}

/// Remove staging partitions and restore disk to pre-installation state.
/// Requires typed confirmation "OSWORLD".
#[tauri::command]
fn cleanup_staging(confirmation: String) -> Result<()> {
    if confirmation != "OSWORLD" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly OSWORLD".to_string(),
        ));
    }

    #[cfg(windows)]
    {
        // Find OSWORLDBOOT partition
        let osworld_label = find_volume_by_label("OSWORLDBOOT");
        if osworld_label.is_none() {
            return Err(InstallerError::SystemCheckFailed(
                "OSWORLDBOOT partition not found. Nothing to clean up.".to_string(),
            ));
        }

        // Find Linux raw partition (last partition on system disk)
        let disk_info = get_system_disk_info()?;
        let disk_index = disk_info.0;

        // Remove Linux partition (last one on disk)
        let linux_part = find_linux_partition_number(disk_index);
        if linux_part.is_some() {
            run_diskpart_script(&format!(
                "select disk {}\nselect partition {}\ndelete partition override\n",
                disk_index,
                linux_part.unwrap()
            ))?;
        }

        // Remove OSWORLDBOOT partition
        let osworld_letter = osworld_label.unwrap();
        let osworld_letter_clean = osworld_letter.trim_end_matches(':');

        // Find partition number by drive letter
        let output = run_powershell(&format!(
            "(Get-Partition | Where-Object {{ $_.DriveLetter -eq '{}' }}).PartitionNumber",
            osworld_letter_clean
        ))?;
        let part_num = String::from_utf8_lossy(&output.stdout)
            .trim()
            .parse::<u32>()
            .map_err(|_| {
                InstallerError::InstallationError(
                    "Could not parse OSWORLDBOOT partition number".to_string(),
                )
            })?;

        run_diskpart_script(&format!(
            "select disk {}\nselect partition {}\ndelete partition override\n",
            disk_index, part_num
        ))?;

        // Expand original target drive to reclaim space
        let target_drive = load_staging_state()
            .and_then(|s| s.target_drive_letter)
            .unwrap_or_else(|| "C".to_string());
        run_diskpart_script(&format!(
            "select disk {}\nselect volume {}\nextend\n",
            disk_index, target_drive
        ))?;

        // Remove rEFInd from EFI
        let esp_letter = assign_esp_letter()?;
        let esp_path = format!("{}:\\", esp_letter);
        let refind_path = format!("{}EFI\\refind\\", esp_path);
        let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);

        // Remove rEFInd directories (ignore errors)
        let _ = std::fs::remove_dir_all(&refind_path);
        let _ = std::fs::remove_dir_all(&refind_boot_path);

        remove_esp_letter(&esp_letter)?;

        // Clean up BCD entries for OSWorld Installer
        let output = std::process::Command::new("bcdedit")
            .args(&["/enum"])
            .output()
            .map_err(|e| {
                InstallerError::InstallationError(format!("bcdedit enum failed: {}", e))
            })?;
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if line.contains("OSWorld Installer") {
                if let Some(guid) = line.split('{').nth(1).and_then(|s| s.split('}').next()) {
                    let full_guid = format!("{{{}}}", guid);
                    let _ = std::process::Command::new("bcdedit")
                        .args(&["/delete", &full_guid, "/cleanup"])
                        .status();
                }
            }
        }

        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = confirmation;
        Err(InstallerError::SystemCheckFailed(
            "cleanup_staging is only supported on Windows".to_string(),
        ))
    }
}

/// Rollback staging changes automatically.
/// Reads staging-state.json and reverses every change made.
/// If state file is missing, performs best-effort scan and rollback.
#[tauri::command]
fn rollback_staging(confirmation: String) -> Result<RollbackStatus> {
    if confirmation != "ROLLBACK" {
        return Err(InstallerError::ValidationError(
            "Confirmation must be exactly ROLLBACK".to_string(),
        ));
    }

    #[cfg(windows)]
    {
        let mut actions: Vec<RollbackAction> = Vec::new();
        let mut manual_steps: Vec<String> = Vec::new();

        append_rollback_log("Rollback initiated.");

        let state = match load_staging_state() {
            Some(s) => {
                append_rollback_log(&format!(
                    "Loaded state. Stage completed: {}",
                    s.stage_completed
                ));
                s
            }
            None => {
                append_rollback_log("No state file found. Attempting best-effort rollback.");
                manual_steps.push(
                    "No staging state file found. Manual cleanup may be required.".to_string(),
                );
                // Best-effort: try to find and remove OSWORLDBOOT
                let disk_info = get_system_disk_info()?;
                StagingState {
                    timestamp: "0".to_string(),
                    disk_index: disk_info.0,
                    target_drive_letter: None,
                    original_target_drive_size_mb: None,
                    efi_entries_before: vec![],
                    osworldboot_partition_number: None,
                    linux_partition_number: None,
                    osworldboot_letter: None,
                    stage_completed: "unknown".to_string(),
                }
            }
        };

        let disk_index = state.disk_index;

        // Step 1: Remove BCD entries for OSWorld Installer / rEFInd
        append_rollback_log("Removing BCD entries...");
        let output = std::process::Command::new("bcdedit")
            .args(&["/enum"])
            .output();
        if let Ok(o) = output {
            let stdout = String::from_utf8_lossy(&o.stdout);
            for line in stdout.lines() {
                if line.contains("OSWorld Installer") || line.contains("rEFInd") {
                    if let Some(guid) = line.split('{').nth(1).and_then(|s| s.split('}').next()) {
                        let full_guid = format!("{{{}}}", guid);
                        let del_result = std::process::Command::new("bcdedit")
                            .args(&["/delete", &full_guid, "/cleanup"])
                            .status();
                        if del_result.map(|s| s.success()).unwrap_or(false) {
                            actions.push(RollbackAction {
                                description: format!("Removed BCD entry: {}", full_guid),
                                success: true,
                                warning: None,
                            });
                        } else {
                            actions.push(RollbackAction {
                                description: format!("Failed to remove BCD entry: {}", full_guid),
                                success: false,
                                warning: Some(
                                    "You may need to remove this entry manually with bcdedit"
                                        .to_string(),
                                ),
                            });
                        }
                    }
                }
            }
        }

        // Step 2: Restore Windows Boot Manager as default
        append_rollback_log("Restoring Windows Boot Manager...");
        let win_boot_result = run_powershell(
            "$bootmgr = bcdedit /enum firmware | Select-String -Pattern 'bootmgr' | Select-Object -First 1; \
             if ($bootmgr) { $guid = ($bootmgr -split '\\s+')[1]; bcdedit /displayorder $guid /addfirst | Out-Null; Write-Output 'OK' } else { Write-Output 'MISSING' }"
        );
        match win_boot_result {
            Ok(o) if String::from_utf8_lossy(&o.stdout).trim() == "OK" => {
                actions.push(RollbackAction {
                    description: "Restored Windows Boot Manager as default".to_string(),
                    success: true,
                    warning: None,
                });
            }
            _ => {
                actions.push(RollbackAction {
                    description: "Could not restore Windows Boot Manager automatically".to_string(),
                    success: false,
                    warning: Some(
                        "Use BIOS/UEFI settings to select Windows Boot Manager manually"
                            .to_string(),
                    ),
                });
                manual_steps.push(
                    "Select Windows Boot Manager in your UEFI firmware settings.".to_string(),
                );
            }
        }

        // Step 3: Remove rEFInd files from EFI
        append_rollback_log("Removing rEFInd from EFI...");
        if let Ok(esp_letter) = assign_esp_letter() {
            let esp_path = format!("{}:\\", esp_letter);
            let refind_path = format!("{}EFI\\refind\\", esp_path);
            let refind_boot_path = format!("{}EFI\\BOOT\\", esp_path);
            let _ = std::fs::remove_dir_all(&refind_path);
            let _ = std::fs::remove_dir_all(&refind_boot_path);
            let _ = remove_esp_letter(&esp_letter);
            actions.push(RollbackAction {
                description: "Removed rEFInd files from EFI System Partition".to_string(),
                success: true,
                warning: None,
            });
        } else {
            actions.push(RollbackAction {
                description: "Could not mount EFI to remove rEFInd files".to_string(),
                success: false,
                warning: Some("You may need to remove \\EFI\\refind manually".to_string()),
            });
        }

        // Step 4: Remove OSWORLDBOOT partition
        append_rollback_log("Removing OSWORLDBOOT partition...");
        let osworld_part = state.osworldboot_partition_number
            .or_else(|| {
                let output = run_powershell(&format!(
                    "(Get-Partition -DiskNumber {} | Where-Object {{ (Get-Volume -Partition $_).FileSystemLabel -eq 'OSWORLDBOOT' }}).PartitionNumber",
                    disk_index
                )).ok()?;
                String::from_utf8_lossy(&output.stdout).trim().parse::<u32>().ok()
            });

        if let Some(part_num) = osworld_part {
            let del_result = run_diskpart_script(&format!(
                "select disk {}\nselect partition {}\ndelete partition override\n",
                disk_index, part_num
            ));
            match del_result {
                Ok(_) => {
                    actions.push(RollbackAction {
                        description: format!("Deleted OSWORLDBOOT partition {}", part_num),
                        success: true,
                        warning: None,
                    });
                }
                Err(e) => {
                    actions.push(RollbackAction {
                        description: format!("Failed to delete OSWORLDBOOT partition: {}", e),
                        success: false,
                        warning: Some(
                            "Use Disk Management to delete the OSWORLDBOOT partition".to_string(),
                        ),
                    });
                    manual_steps.push(
                        "Delete the OSWORLDBOOT partition in Windows Disk Management.".to_string(),
                    );
                }
            }
        } else {
            actions.push(RollbackAction {
                description: "OSWORLDBOOT partition not found (may already be removed)".to_string(),
                success: true,
                warning: None,
            });
        }

        // Step 5: Remove raw Linux partition
        append_rollback_log("Removing Linux partition...");
        let linux_part = state
            .linux_partition_number
            .or_else(|| find_linux_partition_number(disk_index));

        if let Some(part_num) = linux_part {
            // Make sure it's not the same as OSWORLDBOOT
            if Some(part_num) != osworld_part {
                let del_result = run_diskpart_script(&format!(
                    "select disk {}\nselect partition {}\ndelete partition override\n",
                    disk_index, part_num
                ));
                match del_result {
                    Ok(_) => {
                        actions.push(RollbackAction {
                            description: format!("Deleted Linux partition {}", part_num),
                            success: true,
                            warning: None,
                        });
                    }
                    Err(e) => {
                        actions.push(RollbackAction {
                            description: format!("Failed to delete Linux partition: {}", e),
                            success: false,
                            warning: Some(
                                "Use Disk Management to delete the raw Linux partition".to_string(),
                            ),
                        });
                        manual_steps.push(
                            "Delete the raw Linux partition in Windows Disk Management."
                                .to_string(),
                        );
                    }
                }
            }
        } else {
            actions.push(RollbackAction {
                description: "Linux partition not found (may already be removed)".to_string(),
                success: true,
                warning: None,
            });
        }

        // Step 6: Expand C: drive
        append_rollback_log("Expanding C: drive...");
        let extend_result = run_diskpart_script(&format!(
            "select disk {}\nselect volume C\nextend\n",
            disk_index
        ));
        match extend_result {
            Ok(_) => {
                actions.push(RollbackAction {
                    description: "Expanded C: drive to reclaim space".to_string(),
                    success: true,
                    warning: None,
                });
            }
            Err(_) => {
                actions.push(RollbackAction {
                    description: "Could not automatically expand C: drive".to_string(),
                    success: false,
                    warning: Some("You can expand C: manually in Disk Management".to_string()),
                });
                manual_steps.push("Right-click C: in Disk Management and select 'Extend Volume' to reclaim space.".to_string());
            }
        }

        // Step 7: Clean up state file
        let state_path = std::path::Path::new(r"C:\ProgramData\OSWorld\staging-state.json");
        if state_path.exists() {
            let _ = std::fs::remove_file(state_path);
        }

        append_rollback_log("Rollback complete.");

        let all_success = actions.iter().all(|a| a.success) && manual_steps.is_empty();

        Ok(RollbackStatus {
            success: all_success,
            actions,
            manual_steps,
            log_path: r"C:\ProgramData\OSWorld\logs\rollback.log".to_string(),
        })
    }
    #[cfg(not(windows))]
    {
        let _ = confirmation;
        Err(InstallerError::SystemCheckFailed(
            "rollback_staging is only supported on Windows".to_string(),
        ))
    }
}

// ==================== Main Function ====================

fn main() {
    std::panic::set_hook(Box::new(|info| {
        let msg = format!("PANIC: {}\n", info);
        let _ = std::fs::write(r"C:\osworld-panic.log", msg);
    }));
    tauri::Builder::default()
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![
            set_install_type,
            get_config,
            save_config_to_json,
            detect_system_info,
            detect_pc_manufacturer,
            set_secure_boot_strategy,
            get_available_disks,
            set_user_config,
            set_disk_config,
            set_edition,
            set_app_customization,
            get_edition_payment_url,
            verify_edition_payment,
            start_installation,
            cancel_installation,
            calculate_estimated_time,
            prepare_staging,
            download_and_stage_iso,
            download_iso,
            write_config,
            install_refind,
            reboot_to_installer,
            cleanup_staging,
            rollback_staging,
            verify_installation,
            detect_altos_installation,
            remove_altos_partitions,
            restore_windows_bootloader,
            remove_refind_files,
            mark_post_install_seen,
            set_refind_default,
            write_test_state,
            set_test_mode,
            suspend_bitlocker,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_install_config_json_roundtrip() {
        let original = InstallConfig {
            install_type: Some(InstallType::DualBoot),
            windows_version: Some("Windows 11".to_string()),
            disk_free_space_gb: Some(500),
            ram_gb: Some(16),
            cpu_info: Some("Intel i7".to_string()),
            secure_boot_enabled: Some(true),
            secure_boot_strategy: Some("mok_enrollment".to_string()),
            bitlocker_enabled: Some(false),
            selected_disk: Some("Disk 0".to_string()),
            linux_size_gb: Some(100),
            filesystem: Some("ext4".to_string()),
            encrypt: Some(true),
            luks_password: Some("secret".to_string()),
            username: Some("user".to_string()),
            computer_name: Some("pc".to_string()),
            password: Some("pass1234".to_string()),
            edition: Some(Edition::Home),
            browser: Some("brave".to_string()),
            email_client: Some("thunderbird".to_string()),
            music_player: Some("spotify".to_string()),
            include_office_suite: Some(true),
        };

        let json = serde_json::to_string(&original).unwrap();
        let deserialized: InstallConfig = serde_json::from_str(&json).unwrap();

        assert_eq!(original.install_type, deserialized.install_type);
        assert_eq!(original.windows_version, deserialized.windows_version);
        assert_eq!(original.disk_free_space_gb, deserialized.disk_free_space_gb);
        assert_eq!(original.ram_gb, deserialized.ram_gb);
        assert_eq!(original.cpu_info, deserialized.cpu_info);
        assert_eq!(
            original.secure_boot_enabled,
            deserialized.secure_boot_enabled
        );
        assert_eq!(
            original.secure_boot_strategy,
            deserialized.secure_boot_strategy
        );
        assert_eq!(original.bitlocker_enabled, deserialized.bitlocker_enabled);
        assert_eq!(original.selected_disk, deserialized.selected_disk);
        assert_eq!(original.linux_size_gb, deserialized.linux_size_gb);
        assert_eq!(original.filesystem, deserialized.filesystem);
        assert_eq!(original.encrypt, deserialized.encrypt);
        assert_eq!(original.luks_password, deserialized.luks_password);
        assert_eq!(original.username, deserialized.username);
        assert_eq!(original.computer_name, deserialized.computer_name);
        assert_eq!(original.password, deserialized.password);
    }

    #[test]
    fn test_install_config_default() {
        let config = InstallConfig::default();
        assert!(config.install_type.is_none());
        assert!(config.windows_version.is_none());
        assert!(config.disk_free_space_gb.is_none());
        assert!(config.ram_gb.is_none());
        assert!(config.cpu_info.is_none());
        assert!(config.secure_boot_enabled.is_none());
        assert!(config.secure_boot_strategy.is_none());
        assert!(config.bitlocker_enabled.is_none());
        assert!(config.selected_disk.is_none());
        assert!(config.linux_size_gb.is_none());
        assert!(config.filesystem.is_none());
        assert!(config.encrypt.is_none());
        assert!(config.luks_password.is_none());
        assert!(config.username.is_none());
        assert!(config.computer_name.is_none());
        assert!(config.password.is_none());
    }

    #[test]
    fn test_clamp_linux_size() {
        assert_eq!(clamp_linux_size(10, 100), 20);
        assert_eq!(clamp_linux_size(80, 100), 50);
        assert_eq!(clamp_linux_size(30, 100), 30);
        assert_eq!(clamp_linux_size(20, 40), 20);
        assert_eq!(clamp_linux_size(100, 30), 20);
    }

    #[test]
    fn test_lookup_manufacturer() {
        let dell = lookup_manufacturer("Dell Inc.");
        assert_eq!(dell.manufacturer, "Dell");
        assert_eq!(dell.boot_menu_key, "F12");
        assert_eq!(dell.bios_key, "F2");

        let hp = lookup_manufacturer("HP");
        assert_eq!(hp.manufacturer, "HP");
        assert_eq!(hp.boot_menu_key, "F10");
        assert_eq!(hp.bios_key, "ESC");

        let hp2 = lookup_manufacturer("Hewlett-Packard");
        assert_eq!(hp2.manufacturer, "HP");
        assert_eq!(hp2.boot_menu_key, "F10");
        assert_eq!(hp2.bios_key, "ESC");

        let lenovo = lookup_manufacturer("LENOVO");
        assert_eq!(lenovo.manufacturer, "Lenovo");
        assert_eq!(lenovo.boot_menu_key, "F12");
        assert_eq!(lenovo.bios_key, "F1");

        let asus = lookup_manufacturer("ASUSTeK COMPUTER INC.");
        assert_eq!(asus.manufacturer, "ASUS");
        assert_eq!(asus.boot_menu_key, "F8");
        assert_eq!(asus.bios_key, "DEL");

        let acer = lookup_manufacturer("Acer");
        assert_eq!(acer.manufacturer, "Acer");
        assert_eq!(acer.boot_menu_key, "F12");
        assert_eq!(acer.bios_key, "DEL");

        let msi = lookup_manufacturer("Micro-Star International");
        assert_eq!(msi.manufacturer, "MSI");
        assert_eq!(msi.boot_menu_key, "F11");
        assert_eq!(msi.bios_key, "DEL");

        let unknown = lookup_manufacturer("UnknownXYZ Corp");
        assert_eq!(unknown.manufacturer, "Generic");
        assert_eq!(unknown.boot_menu_key, "F2 / F10 / F12");
        assert_eq!(unknown.bios_key, "DEL / F2");
    }

    #[test]
    fn test_error_display_formatting() {
        let err = InstallerError::ValidationError("bad input".to_string());
        assert_eq!(err.to_string(), "Validation error: bad input");
    }

    #[test]
    fn test_set_disk_config_stores_values() {
        let state = AppState::new();
        set_disk_config_impl(
            "Disk 0".to_string(),
            100,
            Some("ext4".to_string()),
            Some(true),
            Some("secret123".to_string()),
            &state,
        )
        .unwrap();

        let config = state.config.lock().unwrap();
        assert_eq!(config.selected_disk, Some("Disk 0".to_string()));
        assert_eq!(config.linux_size_gb, Some(100));
        assert_eq!(config.filesystem, Some("ext4".to_string()));
        assert_eq!(config.encrypt, Some(true));
        assert_eq!(config.luks_password, Some("secret123".to_string()));
    }

    #[test]
    fn test_set_user_config_password_validation() {
        let state = AppState::new();

        // Password too short
        let result = set_user_config_impl(
            "user".to_string(),
            "pc".to_string(),
            "short".to_string(),
            "short".to_string(),
            &state,
        );
        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err().to_string(),
            "Validation error: Password must be at least 8 characters"
        );

        // Matching passwords with 8+ characters
        let result = set_user_config_impl(
            "user".to_string(),
            "pc".to_string(),
            "password123".to_string(),
            "password123".to_string(),
            &state,
        );
        assert!(result.is_ok());

        let config = state.config.lock().unwrap();
        assert_eq!(config.username, Some("user".to_string()));
        assert_eq!(config.password, Some("password123".to_string()));
    }

    #[test]
    fn test_mock_secure_boot() {
        std::env::set_var("MOCK_SECURE_BOOT", "true");
        assert_eq!(check_secure_boot(), Some(true));
        std::env::set_var("MOCK_SECURE_BOOT", "false");
        assert_eq!(check_secure_boot(), Some(false));
        std::env::remove_var("MOCK_SECURE_BOOT");
        assert_eq!(check_secure_boot(), None);
    }

    #[test]
    fn test_mock_bitlocker() {
        std::env::set_var("MOCK_BITLOCKER", "true");
        assert_eq!(check_bitlocker(), Some(true));
        std::env::remove_var("MOCK_BITLOCKER");
        assert_eq!(check_bitlocker(), None);
    }

    #[test]
    fn test_mock_free_space() {
        std::env::set_var("MOCK_FREE_SPACE_GB", "500");
        assert_eq!(get_disk_free_space("C"), Some(500));
        std::env::remove_var("MOCK_FREE_SPACE_GB");
        assert_eq!(get_disk_free_space("C"), Some(250));
    }

    #[test]
    fn test_mock_windows_version() {
        let rt = tokio::runtime::Runtime::new().unwrap();

        std::env::set_var("MOCK_WINDOWS_VERSION", "Windows 10 Home");
        let version = rt.block_on(detect_windows_version()).unwrap();
        assert_eq!(version, "Windows 10 Home");

        std::env::remove_var("MOCK_WINDOWS_VERSION");
        let version = rt.block_on(detect_windows_version()).unwrap();
        assert_eq!(version, "Windows 11 Pro (23H2)");
    }
}

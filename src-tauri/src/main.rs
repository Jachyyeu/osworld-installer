// OSWorld Installer - Tauri v2 Application
// Main Rust backend with system detection and installation logic

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::{Manager, State, Emitter};
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
    pub bitlocker_enabled: Option<bool>,
    pub selected_disk: Option<String>,
    pub linux_size_gb: Option<u64>,
    pub username: Option<String>,
    pub computer_name: Option<String>,
    pub password: Option<String>,
    pub edition: Option<Edition>,
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
    Create,
}

impl Edition {
    pub fn price(&self) -> &'static str {
        match self {
            Edition::Home => "Free",
            Edition::Gaming => "$9.99",
            Edition::Create => "$14.99",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Edition::Home => "Essential features for everyday computing, web browsing, and productivity.",
            Edition::Gaming => "Optimized for gaming with latest drivers, Steam pre-installed, and performance tweaks.",
            Edition::Create => "Professional tools for content creation, video editing, and development workflows.",
        }
    }
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

pub type Result<T> = std::result::Result<T, InstallerError>;

// Application state to store configuration across windows
pub struct AppState {
    config: Mutex<InstallConfig>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            config: Mutex::new(InstallConfig::default()),
        }
    }
}

// System information structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SystemInfo {
    pub windows_version: String,
    pub disk_free_space_gb: u64,
    pub ram_gb: u64,
    pub cpu_info: String,
    pub secure_boot_enabled: bool,
    pub bitlocker_enabled: bool,
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

// ==================== Tauri Commands ====================

/// Set the installation type (Dual Boot or Replace Windows)
#[tauri::command]
fn set_install_type(install_type: String, state: State<AppState>) -> Result<()> {
    let mut config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    config.install_type = match install_type.as_str() {
        "dualboot" => Some(InstallType::DualBoot),
        "replace" => Some(InstallType::ReplaceWindows),
        _ => return Err(InstallerError::ValidationError(
            "Invalid install type".to_string()
        )),
    };
    
    Ok(())
}

/// Get the current installation configuration
#[tauri::command]
fn get_config(state: State<AppState>) -> Result<InstallConfig> {
    let config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    Ok(config.clone())
}

/// Save configuration to JSON file for next stage
#[tauri::command]
fn save_config_to_json(path: String, state: State<AppState>) -> Result<()> {
    let config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    let json = serde_json::to_string_pretty(&*config).map_err(|e| {
        InstallerError::Unknown(format!("Failed to serialize config: {}", e))
    })?;
    
    std::fs::write(&path, json).map_err(|e| {
        InstallerError::Unknown(format!("Failed to write config file: {}", e))
    })?;
    
    Ok(())
}

/// Detect system information (Windows version, RAM, CPU, etc.)
#[tauri::command]
async fn detect_system_info() -> Result<SystemInfo> {
    // Use sysinfo to get system information
    let mut sys = sysinfo::System::new_all();
    sys.refresh_all();
    
    // Get RAM (in GB)
    let ram_gb = sys.total_memory() / 1024 / 1024 / 1024;
    
    // Get CPU info
    let cpu_info = sys.cpus().first()
        .map(|cpu| cpu.brand().to_string())
        .unwrap_or_else(|| "Unknown CPU".to_string());
    
    // Get disk free space using Windows GetDiskFreeSpaceExW
    let disk_free_space_gb = get_disk_free_space().unwrap_or(0);
    
    // Detect Windows version from Registry
    let windows_version = detect_windows_version().await?;
    
    // Check Secure Boot status from Registry
    let secure_boot_enabled = check_secure_boot().unwrap_or(false);
    
    // Check BitLocker status via WMI
    let bitlocker_enabled = check_bitlocker().unwrap_or(false);
    
    Ok(SystemInfo {
        windows_version,
        disk_free_space_gb,
        ram_gb,
        cpu_info,
        secure_boot_enabled,
        bitlocker_enabled,
    })
}

/// Get list of available disks
#[tauri::command]
fn get_available_disks() -> Result<Vec<DiskInfo>> {
    #[cfg(windows)]
    {
        use wmi::{COMLibrary, WMIConnection};
        use serde::Deserialize;

        #[derive(Deserialize, Debug)]
        struct Win32DiskDrive {
            #[serde(rename = "Model")]
            model: String,
            #[serde(rename = "Size")]
            size: Option<i64>,
            #[serde(rename = "Index")]
            index: u32,
            #[serde(rename = "MediaType")]
            media_type: Option<String>,
        }

        #[derive(Deserialize, Debug)]
        struct Win32LogicalDisk {
            #[serde(rename = "DeviceID")]
            device_id: String,
            #[serde(rename = "Size")]
            size: Option<i64>,
            #[serde(rename = "FreeSpace")]
            free_space: Option<i64>,
            #[serde(rename = "DriveType")]
            drive_type: u32,
            #[serde(rename = "VolumeName")]
            volume_name: Option<String>,
        }

        let com = COMLibrary::new().map_err(|e| {
            InstallerError::SystemCheckFailed(format!("COM init failed: {}", e))
        })?;

        let wmi = WMIConnection::new(com).map_err(|e| {
            InstallerError::SystemCheckFailed(format!("WMI connection failed: {}", e))
        })?;

        let disk_drives: Vec<Win32DiskDrive> = wmi
            .raw_query("SELECT * FROM Win32_DiskDrive")
            .map_err(|e| InstallerError::SystemCheckFailed(format!("WMI query failed: {}", e)))?;

        let logical_disks: Vec<Win32LogicalDisk> = wmi
            .raw_query("SELECT * FROM Win32_LogicalDisk WHERE DriveType=3")
            .map_err(|e| InstallerError::SystemCheckFailed(format!("WMI query failed: {}", e)))?;

        let mut disks = Vec::new();

        // Present logical fixed disks (DriveType=3) — these are what users select
        for ld in logical_disks {
            if ld.drive_type != 3 {
                continue;
            }

            let size_gb = ld.size.map(|s| (s as u64) / (1024 * 1024 * 1024)).unwrap_or(0);
            let free_gb = ld.free_space.map(|f| (f as u64) / (1024 * 1024 * 1024)).unwrap_or(0);

            let name = match &ld.volume_name {
                Some(vol) if !vol.is_empty() => {
                    format!("{} ({}:)", ld.device_id.trim_end_matches(':'), vol)
                }
                _ => ld.device_id.clone(),
            };

            disks.push(DiskInfo {
                name,
                size_gb,
                free_space_gb: free_gb,
            });
        }

        // Fallback to physical disks if no logical fixed disks were found
        if disks.is_empty() {
            for drive in disk_drives {
                let is_fixed = drive.media_type.as_deref()
                    .map(|m| m.contains("Fixed"))
                    .unwrap_or(false);

                if !is_fixed {
                    continue;
                }

                let size_gb = drive.size.map(|s| (s as u64) / (1024 * 1024 * 1024)).unwrap_or(0);
                disks.push(DiskInfo {
                    name: format!("Disk {} ({})", drive.index, drive.model.trim()),
                    size_gb,
                    free_space_gb: 0,
                });
            }
        }

        Ok(disks)
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

/// Set disk selection and Linux partition size
#[tauri::command]
fn set_disk_config(disk_name: String, linux_size_gb: u64, state: State<AppState>) -> Result<()> {
    let mut config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    config.selected_disk = Some(disk_name);
    config.linux_size_gb = Some(linux_size_gb);
    
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
    // Validate username (lowercase only)
    if username != username.to_lowercase() {
        return Err(InstallerError::ValidationError(
            "Username must be lowercase only".to_string()
        ));
    }
    
    if username.len() < 3 {
        return Err(InstallerError::ValidationError(
            "Username must be at least 3 characters".to_string()
        ));
    }
    
    // Validate password (8+ characters)
    if password.len() < 8 {
        return Err(InstallerError::ValidationError(
            "Password must be at least 8 characters".to_string()
        ));
    }
    
    // Check password match
    if password != confirm_password {
        return Err(InstallerError::ValidationError(
            "Passwords do not match".to_string()
        ));
    }
    
    let mut config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    config.username = Some(username);
    config.computer_name = Some(computer_name);
    config.password = Some(password);
    
    Ok(())
}

/// Set edition selection
#[tauri::command]
fn set_edition(edition: String, state: State<AppState>) -> Result<()> {
    let mut config = state.config.lock().map_err(|e| {
        InstallerError::Unknown(format!("Failed to lock state: {}", e))
    })?;
    
    config.edition = match edition.as_str() {
        "home" => Some(Edition::Home),
        "gaming" => Some(Edition::Gaming),
        "create" => Some(Edition::Create),
        _ => return Err(InstallerError::ValidationError(
            "Invalid edition".to_string()
        )),
    };
    
    Ok(())
}

/// Start installation process
#[tauri::command]
async fn start_installation(app: tauri::AppHandle) -> Result<()> {
    let steps = vec![
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

// ==================== Helper Functions ====================

#[cfg(windows)]
fn to_wide(s: &str) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    std::ffi::OsStr::new(s).encode_wide().chain(Some(0)).collect()
}

#[cfg(windows)]
fn reg_query_string(hkey: isize, subkey: &str, value: &str) -> Option<String> {
    use windows_sys::Win32::System::Registry::{
        RegOpenKeyExW, RegQueryValueExW, RegCloseKey, KEY_READ,
    };

    let subkey_wide = to_wide(subkey);
    let value_wide = to_wide(value);
    let mut h: isize = 0;

    let status = unsafe {
        RegOpenKeyExW(hkey, subkey_wide.as_ptr(), 0, KEY_READ, &mut h)
    };

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

    let u16_slice = unsafe {
        std::slice::from_raw_parts(buf.as_ptr() as *const u16, buf.len() / 2)
    };

    let u16_vec: Vec<u16> = u16_slice.iter().copied().take_while(|&c| c != 0).collect();
    String::from_utf16(&u16_vec).ok()
}

#[cfg(windows)]
fn reg_query_dword(hkey: isize, subkey: &str, value: &str) -> Option<u32> {
    use windows_sys::Win32::System::Registry::{
        RegOpenKeyExW, RegQueryValueExW, RegCloseKey, KEY_READ,
    };

    let subkey_wide = to_wide(subkey);
    let value_wide = to_wide(value);
    let mut h: isize = 0;

    let status = unsafe {
        RegOpenKeyExW(hkey, subkey_wide.as_ptr(), 0, KEY_READ, &mut h)
    };

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

async fn detect_windows_version() -> Result<String> {
    #[cfg(windows)]
    {
        let product_name = reg_query_string(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ProductName",
        )
        .unwrap_or_else(|| "Windows".to_string());

        let display_version = reg_query_string(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "DisplayVersion",
        );

        let release_id = reg_query_string(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE,
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
    #[cfg(not(windows))]
    {
        Ok("Windows 11 Pro (23H2)".to_string())
    }
}

fn get_disk_free_space() -> Option<u64> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::ULARGE_INTEGER;
        use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

        let path = to_wide("C:\\");
        let mut free_bytes: ULARGE_INTEGER = unsafe { std::mem::zeroed() };

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

        let bytes = unsafe { free_bytes.QuadPart };
        Some(bytes / (1024 * 1024 * 1024))
    }
    #[cfg(not(windows))]
    {
        Some(250)
    }
}

fn check_secure_boot() -> Option<bool> {
    #[cfg(windows)]
    {
        let val = reg_query_dword(
            windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE,
            r"SYSTEM\CurrentControlSet\Control\SecureBoot\State",
            "UEFISecureBootEnabled",
        );
        Some(val.unwrap_or(0) != 0)
    }
    #[cfg(not(windows))]
    {
        Some(false)
    }
}

fn check_bitlocker() -> Option<bool> {
    #[cfg(windows)]
    {
        use wmi::{COMLibrary, WMIConnection};
        use serde::Deserialize;

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
    #[cfg(not(windows))]
    {
        Some(false)
    }
}

// ==================== Main Function ====================

fn main() {
    tauri::Builder::default()
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![
            set_install_type,
            get_config,
            save_config_to_json,
            detect_system_info,
            get_available_disks,
            set_disk_config,
            set_user_config,
            set_edition,
            start_installation,
            cancel_installation,
            calculate_estimated_time,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

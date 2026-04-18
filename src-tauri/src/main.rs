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
    
    // Get disk free space (simplified - in production would use Windows APIs)
    let disk_free_space_gb = get_disk_free_space().unwrap_or(0);
    
    // Detect Windows version
    let windows_version = detect_windows_version().await?;
    
    // Check Secure Boot status
    let secure_boot_enabled = check_secure_boot().unwrap_or(false);
    
    // Check BitLocker status
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
    // In production, this would use Windows WMI to get actual disk information
    // For now, returning mock data
    let disks = vec![
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
    ];
    Ok(disks)
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

async fn detect_windows_version() -> Result<String> {
    // In production, this would read from Windows Registry
    // For now, return a mock version
    Ok("Windows 11 Pro (23H2)".to_string())
}

fn get_disk_free_space() -> Option<u64> {
    // In production, this would use GetDiskFreeSpaceExW
    Some(250)
}

fn check_secure_boot() -> Option<bool> {
    // In production, this would check UEFI Secure Boot variable
    Some(true)
}

fn check_bitlocker() -> Option<bool> {
    // In production, this would query BitLocker status via WMI
    Some(false)
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

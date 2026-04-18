// Tauri API helper functions
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { InstallConfig, SystemInfo, DiskInfo, InstallProgress, InstallType, Edition, StagingInfo, DownloadProgress, DownloadProgressEvent } from '../types';

// Invoke commands with proper typing
export async function setInstallType(installType: InstallType): Promise<void> {
  return invoke('set_install_type', { installType });
}

export async function getConfig(): Promise<InstallConfig> {
  return invoke('get_config');
}

export async function saveConfigToJson(path: string): Promise<void> {
  return invoke('save_config_to_json', { path });
}

export async function detectSystemInfo(): Promise<SystemInfo> {
  return invoke('detect_system_info');
}

export async function getAvailableDisks(): Promise<DiskInfo[]> {
  return invoke('get_available_disks');
}

export async function setDiskConfig(diskName: string, linuxSizeGb: number): Promise<void> {
  return invoke('set_disk_config', { diskName, linuxSizeGb });
}

export async function setUserConfig(
  username: string,
  computerName: string,
  password: string,
  confirmPassword: string
): Promise<void> {
  return invoke('set_user_config', { 
    username, 
    computerName, 
    password, 
    confirmPassword 
  });
}

export async function setEdition(edition: Edition): Promise<void> {
  return invoke('set_edition', { edition });
}

export async function startInstallation(): Promise<void> {
  return invoke('start_installation');
}

export async function cancelInstallation(): Promise<void> {
  return invoke('cancel_installation');
}

export async function calculateEstimatedTime(linuxSizeGb: number): Promise<string> {
  return invoke('calculate_estimated_time', { linuxSizeGb });
}

// Staging commands
export async function prepareStaging(config: InstallConfig, confirmation: string): Promise<StagingInfo> {
  return invoke('prepare_staging', { config, confirmation });
}

export async function downloadAndStageIso(targetDriveLetter: string, config: InstallConfig): Promise<DownloadProgress> {
  return invoke('download_and_stage_iso', { targetDriveLetter, config });
}

export async function installRefind(): Promise<void> {
  return invoke('install_refind');
}

export async function rebootToInstaller(): Promise<void> {
  return invoke('reboot_to_installer');
}

// Event listeners
export function onInstallProgress(callback: (progress: InstallProgress) => void) {
  return listen<InstallProgress>('install-progress', (event) => {
    callback(event.payload);
  });
}

export function onDownloadProgress(callback: (progress: DownloadProgressEvent) => void) {
  return listen<DownloadProgressEvent>('download-progress', (event) => {
    callback(event.payload);
  });
}

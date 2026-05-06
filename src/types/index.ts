// TypeScript types for OSWorld Installer

export type InstallType = 'dualboot' | 'replace';

export interface InstallConfig {
  install_type?: InstallType;
  windows_version?: string;
  disk_free_space_gb?: number;
  ram_gb?: number;
  cpu_info?: string;
  secure_boot_enabled?: boolean;
  bitlocker_enabled?: boolean;
  selected_disk?: string;
  linux_size_gb?: number;
  username?: string;
  computer_name?: string;
  password?: string;
}

export interface SystemInfo {
  windows_version: string;
  disk_free_space_gb: number;
  ram_gb: number;
  cpu_info: string;
  secure_boot_enabled: boolean;
  bitlocker_enabled: boolean;
}

export interface DiskInfo {
  name: string;
  size_gb: number;
  free_space_gb: number;
}

export interface InstallProgress {
  step: string;
  progress_percent: number;
  current_step_index: number;
  total_steps: number;
}

export interface StagingInfo {
  boot_partition_letter: string;
  linux_partition_number: number;
}

export interface DownloadProgress {
  percent: number;
  stage: string;
  bytes_downloaded: number;
  total_bytes: number;
}

export interface DownloadProgressEvent {
  percent: number;
  stage: string;
}

export interface VerificationCheck {
  name: string;
  passed: boolean;
  details: string;
}

export interface VerificationStatus {
  overall_pass: boolean;
  checks: VerificationCheck[];
}

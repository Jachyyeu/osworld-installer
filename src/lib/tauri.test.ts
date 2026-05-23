import { describe, it, expect, vi, beforeEach } from 'vitest';
import { invoke } from '@tauri-apps/api/core';
import {
  setDiskConfig,
  detectPcManufacturer,
  getConfig,
} from './tauri';

describe('Tauri API wrappers', () => {
  beforeEach(() => {
    vi.mocked(invoke).mockClear();
  });

  it('setDiskConfig invokes with correct args', async () => {
    await setDiskConfig('sda', 80, 'ext4', true, 'password123');
    expect(invoke).toHaveBeenCalledWith('set_disk_config', {
      diskName: 'sda',
      linuxSizeGb: 80,
      filesystem: 'ext4',
      encrypt: true,
      luksPassword: 'password123',
    });
  });

  it('detectPcManufacturer invokes correct command', async () => {
    await detectPcManufacturer();
    expect(invoke).toHaveBeenCalledWith('detect_pc_manufacturer');
  });

  it('getConfig invokes correct command', async () => {
    await getConfig();
    expect(invoke).toHaveBeenCalledWith('get_config');
  });
});

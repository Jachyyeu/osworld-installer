import { useState, useEffect } from 'react';
import {
  Cpu,
  HardDrive,
  MemoryStick,
  Shield,
  Lock,
  Monitor,
  AlertTriangle,
  XCircle,
  ArrowRight,
  ArrowLeft,
  RefreshCw
} from 'lucide-react';
import { detectSystemInfo } from '../lib/tauri';
import type { SystemInfo } from '../types';

interface SystemCheckWindowProps {
  onNext: () => void;
  onBack: () => void;
}

interface CheckItemProps {
  icon: React.ReactNode;
  label: string;
  value: string;
  status: 'ok' | 'warning' | 'error' | 'loading';
  warningMessage?: string;
}

function StatusDot({ status }: { status: 'ok' | 'warning' | 'error' | 'loading' }) {
  if (status === 'ok') {
    return <div className="w-2.5 h-2.5 rounded-full bg-altos-success" />;
  }
  if (status === 'warning') {
    return <div className="w-2.5 h-2.5 rounded-full bg-altos-warning" />;
  }
  if (status === 'error') {
    return <div className="w-2.5 h-2.5 rounded-full bg-altos-danger" />;
  }
  return <div className="w-2.5 h-2.5 rounded-full bg-altos-text-secondary animate-pulse" />;
}

function CheckItem({ icon, label, value, status, warningMessage }: CheckItemProps) {
  return (
    <div className="flex items-center gap-4 py-3 border-b border-altos-border last:border-0">
      <div className="w-9 h-9 bg-[#1a1d21] rounded-lg flex items-center justify-center flex-shrink-0 text-altos-blue">
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm text-altos-text-secondary">{label}</p>
        <p className="text-sm font-medium text-altos-text truncate">{value}</p>
        {status === 'loading' && (
          <div className="flex items-center gap-2 mt-1 text-altos-text-secondary">
            <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            <span className="text-xs">Detecting...</span>
          </div>
        )}
        {warningMessage && status !== 'ok' && status !== 'loading' && (
          <p className={`text-xs mt-1 ${status === 'warning' ? 'text-altos-warning' : 'text-altos-danger'}`}>
            {warningMessage}
          </p>
        )}
      </div>
      <div className="flex-shrink-0">
        {status === 'loading' ? (
          <div className="w-5 h-5 rounded-full border-2 border-altos-border border-t-altos-blue animate-spin" />
        ) : (
          <StatusDot status={status} />
        )}
      </div>
    </div>
  );
}

export default function SystemCheckWindow({ onNext, onBack }: SystemCheckWindowProps) {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadSystemInfo = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const info = await detectSystemInfo();
      setSystemInfo(info);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to detect system information');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadSystemInfo();
  }, []);

  const hasBlockingIssues = systemInfo?.secure_boot_enabled || systemInfo?.bitlocker_enabled;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-altos-text">System Check</h2>
        <p className="text-sm text-altos-text-secondary">
          Checking your system for compatibility with AltOS Linux.
        </p>
      </div>

      {/* Error Message */}
      {error && (
        <div className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4">
          <div className="flex items-center gap-2 mb-1">
            <XCircle className="w-5 h-5 text-altos-danger" />
            <span className="font-medium text-altos-text text-sm">Error</span>
          </div>
          <p className="text-sm text-altos-text-secondary">{error}</p>
          <button
            onClick={loadSystemInfo}
            className="mt-3 flex items-center gap-2 text-sm font-medium text-altos-blue hover:text-altos-blue-hover transition-colors duration-150"
          >
            <RefreshCw className="w-4 h-4" />
            Retry
          </button>
        </div>
      )}

      {/* System Checks */}
      <div className="bg-[#1a1d21] border border-altos-border rounded-xl px-4">
        <CheckItem
          icon={<Monitor className="w-5 h-5" />}
          label="Windows Version"
          value={systemInfo?.windows_version || 'Detecting...'}
          status={isLoading ? 'loading' : 'ok'}
        />

        <CheckItem
          icon={<HardDrive className="w-5 h-5" />}
          label="Disk Free Space"
          value={systemInfo ? `${systemInfo.disk_free_space_gb} GB` : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.disk_free_space_gb < 20 ? 'warning' : 'ok'}
          warningMessage={systemInfo && systemInfo.disk_free_space_gb < 20 ?
            'At least 20GB of free space is recommended.' : undefined}
        />

        <CheckItem
          icon={<MemoryStick className="w-5 h-5" />}
          label="RAM"
          value={systemInfo ? `${systemInfo.ram_gb} GB` : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.ram_gb < 4 ? 'warning' : 'ok'}
          warningMessage={systemInfo && systemInfo.ram_gb < 4 ?
            '4GB or more RAM is recommended for optimal performance.' : undefined}
        />

        <CheckItem
          icon={<Cpu className="w-5 h-5" />}
          label="Processor"
          value={systemInfo?.cpu_info || 'Detecting...'}
          status={isLoading ? 'loading' : 'ok'}
        />

        <CheckItem
          icon={<Shield className="w-5 h-5" />}
          label="Secure Boot"
          value={systemInfo ? (systemInfo.secure_boot_enabled ? 'Enabled' : 'Disabled') : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.secure_boot_enabled ? 'error' : 'ok'}
          warningMessage={systemInfo?.secure_boot_enabled ?
            'Please disable Secure Boot in BIOS before continuing.' : undefined}
        />

        <CheckItem
          icon={<Lock className="w-5 h-5" />}
          label="BitLocker"
          value={systemInfo ? (systemInfo.bitlocker_enabled ? 'Enabled' : 'Disabled') : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.bitlocker_enabled ? 'error' : 'ok'}
          warningMessage={systemInfo?.bitlocker_enabled ?
            'BitLocker detected. Suspend encryption first to avoid data loss.' : undefined}
        />
      </div>

      {/* Warning Banner */}
      {hasBlockingIssues && (
        <div className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-altos-danger flex-shrink-0 mt-0.5" />
            <div>
              <h4 className="font-medium text-altos-text text-sm mb-1">Action Required</h4>
              <p className="text-sm text-altos-text-secondary">
                Please resolve the issues above before continuing. These settings may prevent a successful installation.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Navigation Buttons */}
      <div className="flex justify-between pt-2">
        <button
          onClick={onBack}
          disabled={isLoading}
          className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary
            hover:text-altos-text hover:bg-[#1a1d21] transition-colors duration-150 disabled:opacity-50"
        >
          <ArrowLeft className="w-5 h-5" />
          <span>Back</span>
        </button>

        <button
          onClick={onNext}
          disabled={isLoading || !!hasBlockingIssues}
          className={`
            flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
            transition-colors duration-150
            ${!isLoading && !hasBlockingIssues
              ? 'bg-altos-blue hover:bg-altos-blue-hover'
              : 'bg-[#3a3f47] cursor-not-allowed text-altos-text-secondary'
            }
          `}
        >
          <span>Continue</span>
          <ArrowRight className="w-5 h-5" />
        </button>
      </div>
    </div>
  );
}

import { useState, useEffect } from 'react';
import { 
  Cpu, 
  HardDrive, 
  MemoryStick, 
  Shield, 
  Lock, 
  Monitor,
  AlertTriangle,
  CheckCircle,
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

function CheckItem({ icon, label, value, status, warningMessage }: CheckItemProps) {
  return (
    <div className="bg-slate-50 rounded-lg p-4">
      <div className="flex items-start gap-4">
        <div className="w-10 h-10 bg-white rounded-lg shadow-sm flex items-center justify-center flex-shrink-0">
          {icon}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm text-slate-500 mb-1">{label}</p>
          <p className="font-semibold text-slate-800 truncate">{value}</p>
          {status === 'loading' && (
            <div className="flex items-center gap-2 mt-2 text-slate-400">
              <RefreshCw className="w-4 h-4 animate-spin" />
              <span className="text-sm">Detecting...</span>
            </div>
          )}
        </div>
        <div className="flex-shrink-0">
          {status === 'ok' && <CheckCircle className="w-6 h-6 text-green-500" />}
          {status === 'warning' && <AlertTriangle className="w-6 h-6 text-amber-500" />}
          {status === 'error' && <XCircle className="w-6 h-6 text-red-500" />}
          {status === 'loading' && <div className="w-6 h-6 rounded-full border-2 border-slate-200 border-t-primary-500 animate-spin" />}
        </div>
      </div>
      {warningMessage && status !== 'ok' && status !== 'loading' && (
        <div className={`
          mt-3 p-3 rounded-lg text-sm flex items-start gap-2
          ${status === 'warning' ? 'bg-amber-100 text-amber-800' : 'bg-red-100 text-red-800'}
        `}>
          <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>{warningMessage}</span>
        </div>
      )}
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
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-bold text-slate-800">System Check</h2>
        <p className="text-slate-600">
          We're checking your system to ensure compatibility with OSWorld Linux.
        </p>
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
          <div className="flex items-center gap-2 mb-2">
            <XCircle className="w-5 h-5" />
            <span className="font-semibold">Error</span>
          </div>
          <p className="text-sm">{error}</p>
          <button
            onClick={loadSystemInfo}
            className="mt-3 flex items-center gap-2 text-sm font-medium hover:underline"
          >
            <RefreshCw className="w-4 h-4" />
            Retry
          </button>
        </div>
      )}

      {/* System Checks Grid */}
      <div className="grid md:grid-cols-2 gap-4">
        <CheckItem
          icon={<Monitor className="w-5 h-5 text-primary-600" />}
          label="Windows Version"
          value={systemInfo?.windows_version || 'Detecting...'}
          status={isLoading ? 'loading' : 'ok'}
        />
        
        <CheckItem
          icon={<HardDrive className="w-5 h-5 text-primary-600" />}
          label="Disk Free Space"
          value={systemInfo ? `${systemInfo.disk_free_space_gb} GB` : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.disk_free_space_gb < 20 ? 'warning' : 'ok'}
          warningMessage={systemInfo && systemInfo.disk_free_space_gb < 20 ? 
            'At least 20GB of free space is recommended for installation.' : undefined}
        />
        
        <CheckItem
          icon={<MemoryStick className="w-5 h-5 text-primary-600" />}
          label="RAM"
          value={systemInfo ? `${systemInfo.ram_gb} GB` : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.ram_gb < 4 ? 'warning' : 'ok'}
          warningMessage={systemInfo && systemInfo.ram_gb < 4 ? 
            '4GB or more RAM is recommended for optimal performance.' : undefined}
        />
        
        <CheckItem
          icon={<Cpu className="w-5 h-5 text-primary-600" />}
          label="Processor"
          value={systemInfo?.cpu_info || 'Detecting...'}
          status={isLoading ? 'loading' : 'ok'}
        />
        
        <CheckItem
          icon={<Shield className="w-5 h-5 text-primary-600" />}
          label="Secure Boot"
          value={systemInfo ? (systemInfo.secure_boot_enabled ? 'Enabled' : 'Disabled') : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.secure_boot_enabled ? 'error' : 'ok'}
          warningMessage={systemInfo?.secure_boot_enabled ? 
            'Please disable Secure Boot in BIOS before continuing.' : undefined}
        />
        
        <CheckItem
          icon={<Lock className="w-5 h-5 text-primary-600" />}
          label="BitLocker"
          value={systemInfo ? (systemInfo.bitlocker_enabled ? 'Enabled' : 'Disabled') : 'Detecting...'}
          status={isLoading ? 'loading' : systemInfo!.bitlocker_enabled ? 'error' : 'ok'}
          warningMessage={systemInfo?.bitlocker_enabled ? 
            'BitLocker detected. Suspend encryption first to avoid data loss.' : undefined}
        />
      </div>

      {/* Warning Banner */}
      {hasBlockingIssues && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div>
              <h4 className="font-semibold text-red-800 mb-1">Action Required</h4>
              <p className="text-sm text-red-700">
                Please resolve the issues above before continuing. These settings may prevent a successful installation.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Navigation Buttons */}
      <div className="flex justify-between pt-4">
        <button
          onClick={onBack}
          disabled={isLoading}
          className="flex items-center gap-2 px-6 py-3 rounded-lg font-semibold text-slate-600
            hover:bg-slate-100 transition-colors disabled:opacity-50"
        >
          <ArrowLeft className="w-5 h-5" />
          <span>Back</span>
        </button>
        
        <button
          onClick={onNext}
          disabled={isLoading || !!hasBlockingIssues}
          className={`
            flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
            transition-all duration-200
            ${!isLoading && !hasBlockingIssues
              ? 'bg-primary-600 hover:bg-primary-700 shadow-lg hover:shadow-xl'
              : 'bg-slate-300 cursor-not-allowed'
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

import { useState, useEffect } from 'react';
import { 
  HardDrive, 
  ArrowRight, 
  ArrowLeft, 
  Clock,
  Info,
  AlertTriangle,
  CheckCircle
} from 'lucide-react';
import { getAvailableDisks, setDiskConfig, calculateEstimatedTime } from '../lib/tauri';
import type { DiskInfo } from '../types';

interface DiskSelectionWindowProps {
  onNext: () => void;
  onBack: () => void;
}

export default function DiskSelectionWindow({ onNext, onBack }: DiskSelectionWindowProps) {
  const [disks, setDisks] = useState<DiskInfo[]>([]);
  const [selectedDisk, setSelectedDisk] = useState<string | null>(null);
  const [linuxSizeGb, setLinuxSizeGb] = useState<number>(50);
  const [estimatedTime, setEstimatedTime] = useState<string>('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedDiskInfo = disks.find(d => d.name === selectedDisk);
  const maxSizeGb = selectedDiskInfo 
    ? Math.min(100, Math.floor(selectedDiskInfo.free_space_gb * 0.5))
    : 100;
  const minSizeGb = 20;

  useEffect(() => {
    loadDisks();
  }, []);

  useEffect(() => {
    if (linuxSizeGb > 0) {
      updateEstimatedTime();
    }
  }, [linuxSizeGb]);

  const loadDisks = async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const availableDisks = await getAvailableDisks();
      setDisks(availableDisks);
      if (availableDisks.length > 0) {
        setSelectedDisk(availableDisks[0].name);
        const max = Math.min(100, Math.floor(availableDisks[0].free_space_gb * 0.5));
        setLinuxSizeGb(Math.max(minSizeGb, Math.min(50, max)));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load disk information');
    } finally {
      setIsLoading(false);
    }
  };

  const updateEstimatedTime = async () => {
    try {
      const time = await calculateEstimatedTime(linuxSizeGb);
      setEstimatedTime(time);
    } catch (err) {
      setEstimatedTime('');
    }
  };

  const handleContinue = async () => {
    if (!selectedDisk) return;
    
    setIsSaving(true);
    setError(null);
    
    try {
      await setDiskConfig(selectedDisk, linuxSizeGb);
      onNext();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save disk configuration');
      setIsSaving(false);
    }
  };

  const handleDiskChange = (diskName: string) => {
    setSelectedDisk(diskName);
    const disk = disks.find(d => d.name === diskName);
    if (disk) {
      const max = Math.min(100, Math.floor(disk.free_space_gb * 0.5));
      setLinuxSizeGb(Math.max(minSizeGb, Math.min(50, max)));
    }
  };

  const formatSize = (gb: number) => {
    if (gb >= 1000) {
      return `${(gb / 1000).toFixed(1)} TB`;
    }
    return `${gb} GB`;
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-bold text-slate-800">Disk Selection</h2>
        <p className="text-slate-600">
          Choose which disk to install Linux on and how much space to allocate.
        </p>
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="w-5 h-5" />
            <span className="font-semibold">Error</span>
          </div>
          <p className="text-sm">{error}</p>
        </div>
      )}

      {/* Disk Selection */}
      <div className="space-y-3">
        <label className="block text-sm font-semibold text-slate-700">
          Select Disk
        </label>
        {isLoading ? (
          <div className="flex items-center justify-center p-8 bg-slate-50 rounded-lg">
            <div className="w-8 h-8 border-4 border-slate-200 border-t-primary-500 rounded-full animate-spin" />
          </div>
        ) : (
          <div className="space-y-3">
            {disks.map((disk) => (
              <button
                key={disk.name}
                onClick={() => handleDiskChange(disk.name)}
                className={`
                  w-full p-4 rounded-lg border-2 text-left transition-all duration-200
                  ${selectedDisk === disk.name
                    ? 'border-primary-500 bg-primary-50'
                    : 'border-slate-200 hover:border-primary-300 hover:bg-slate-50'
                  }
                `}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className={`
                      w-12 h-12 rounded-lg flex items-center justify-center
                      ${selectedDisk === disk.name ? 'bg-primary-500' : 'bg-slate-100'}
                    `}>
                      <HardDrive className={`
                        w-6 h-6
                        ${selectedDisk === disk.name ? 'text-white' : 'text-slate-600'}
                      `} />
                    </div>
                    <div>
                      <p className="font-semibold text-slate-800">{disk.name}</p>
                      <p className="text-sm text-slate-500">
                        Total: {formatSize(disk.size_gb)} • Free: {formatSize(disk.free_space_gb)}
                      </p>
                    </div>
                  </div>
                  {selectedDisk === disk.name && (
                    <CheckCircle className="w-6 h-6 text-primary-500" />
                  )}
                </div>
                
                {/* Disk usage bar */}
                <div className="mt-3">
                  <div className="h-2 bg-slate-200 rounded-full overflow-hidden">
                    <div 
                      className="h-full bg-primary-500 rounded-full transition-all duration-300"
                      style={{ 
                        width: `${((disk.size_gb - disk.free_space_gb) / disk.size_gb) * 100}%` 
                      }}
                    />
                  </div>
                  <div className="flex justify-between mt-1 text-xs text-slate-500">
                    <span>Used: {formatSize(disk.size_gb - disk.free_space_gb)}</span>
                    <span>Free: {formatSize(disk.free_space_gb)}</span>
                  </div>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Size Slider */}
      {selectedDiskInfo && (
        <div className="bg-slate-50 rounded-lg p-6 space-y-4">
          <div className="flex items-center justify-between">
            <label className="block text-sm font-semibold text-slate-700">
              Linux Partition Size
            </label>
            <span className="text-2xl font-bold text-primary-600">
              {linuxSizeGb} GB
            </span>
          </div>
          
          <input
            type="range"
            min={minSizeGb}
            max={maxSizeGb}
            value={linuxSizeGb}
            onChange={(e) => setLinuxSizeGb(Number(e.target.value))}
            className="w-full h-2 bg-slate-200 rounded-lg appearance-none cursor-pointer accent-primary-600"
          />
          
          <div className="flex justify-between text-sm text-slate-500">
            <span>Min: {minSizeGb} GB</span>
            <span>Max: {maxSizeGb} GB (50% of free space)</span>
          </div>

          {/* Info Box */}
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 flex items-start gap-3">
            <Info className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-blue-800">
              <p className="font-medium mb-1">Partition Layout</p>
              <p>
                Linux will be installed in a new partition. Your Windows data will remain untouched.
              </p>
            </div>
          </div>

          {/* Estimated Time */}
          {estimatedTime && (
            <div className="flex items-center gap-2 text-sm text-slate-600">
              <Clock className="w-4 h-4" />
              <span>Estimated installation time: <strong>{estimatedTime}</strong></span>
            </div>
          )}
        </div>
      )}

      {/* Navigation Buttons */}
      <div className="flex justify-between pt-4">
        <button
          onClick={onBack}
          disabled={isSaving}
          className="flex items-center gap-2 px-6 py-3 rounded-lg font-semibold text-slate-600
            hover:bg-slate-100 transition-colors disabled:opacity-50"
        >
          <ArrowLeft className="w-5 h-5" />
          <span>Back</span>
        </button>
        
        <button
          onClick={handleContinue}
          disabled={!selectedDisk || isLoading || isSaving}
          className={`
            flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
            transition-all duration-200
            ${selectedDisk && !isLoading && !isSaving
              ? 'bg-primary-600 hover:bg-primary-700 shadow-lg hover:shadow-xl'
              : 'bg-slate-300 cursor-not-allowed'
            }
          `}
        >
          {isSaving ? (
            <>
              <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              <span>Saving...</span>
            </>
          ) : (
            <>
              <span>Continue</span>
              <ArrowRight className="w-5 h-5" />
            </>
          )}
        </button>
      </div>
    </div>
  );
}

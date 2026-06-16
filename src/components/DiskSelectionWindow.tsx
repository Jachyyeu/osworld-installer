import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  HardDrive,
  ArrowRight,
  ArrowLeft,
  Clock,
  Info,
  AlertTriangle,
  CheckCircle,
  Monitor,
  Leaf,
  ChevronDown,
  Lock,
} from 'lucide-react';
import { getAvailableDisks, setDiskConfig, calculateEstimatedTime, writeTestState } from '../lib/tauri';
import type { DiskInfo } from '../types';

const TEST_STATE_PATH = 'C:\\\\altos-test-state.json';

interface DiskSelectionWindowProps {
  onNext: () => void;
  onBack: () => void;
  autoplay?: boolean;
}

const FILESYSTEMS = [
  { value: 'ext4', label: 'ext4 — Reliable & fast', desc: 'Best for most users' },
  { value: 'btrfs', label: 'btrfs — Modern & flexible', desc: 'Snapshots, compression' },
  { value: 'xfs', label: 'xfs — High performance', desc: 'Great for large files' },
];

const MIN_SIZE_GB = 20;

export default function DiskSelectionWindow({ onNext, onBack, autoplay = false }: DiskSelectionWindowProps) {
  const [disks, setDisks] = useState<DiskInfo[]>([]);
  const [selectedDisk, setSelectedDisk] = useState<string | null>(null);
  const [linuxSizeGb, setLinuxSizeGb] = useState<number>(50);
  const [estimatedTime, setEstimatedTime] = useState<string>('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [filesystem, setFilesystem] = useState('ext4');
  const [encrypt, setEncrypt] = useState(false);
  const [luksPassword, setLuksPassword] = useState('');
  const [isDragging, setIsDragging] = useState(false);

  const barRef = useRef<HTMLDivElement>(null);

  const selectedDiskInfo = disks.find((d) => d.name === selectedDisk);

  const maxSizeGb = selectedDiskInfo
    ? Math.min(100, Math.floor(selectedDiskInfo.free_space_gb * 0.5))
    : 100;

  const windowsSizeGb = selectedDiskInfo ? selectedDiskInfo.size_gb - selectedDiskInfo.free_space_gb : 0;
  const freeSizeGb = selectedDiskInfo ? selectedDiskInfo.free_space_gb - linuxSizeGb : 0;

  const totalGb = selectedDiskInfo?.size_gb ?? 1;
  const windowsPct = (windowsSizeGb / totalGb) * 100;
  const altosPct = (linuxSizeGb / totalGb) * 100;
  const freePct = (freeSizeGb / totalGb) * 100;

  const formatSize = (gb: number) => {
    if (gb >= 1000) return `${(gb / 1000).toFixed(1)} TB`;
    return `${gb} GB`;
  };

  const loadDisks = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const availableDisks = autoplay
        ? [
            { name: 'Disk 0 (C:)', size_gb: 512, free_space_gb: 200 },
            { name: 'Disk 1 (D:)', size_gb: 1024, free_space_gb: 800 },
          ]
        : await getAvailableDisks();
      setDisks(availableDisks);

      if (availableDisks.length > 0) {
        // Pick the largest disk by total size
        const largest = availableDisks.reduce((max, d) => (d.size_gb > max.size_gb ? d : max), availableDisks[0]);
        setSelectedDisk(largest.name);

        const maxSize = Math.min(100, Math.floor(largest.free_space_gb * 0.5));
        const recommended = Math.max(40, Math.floor(largest.free_space_gb * 0.3));
        const initialSize = Math.max(MIN_SIZE_GB, Math.min(recommended, maxSize));
        setLinuxSizeGb(initialSize);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load disk information');
    } finally {
      setIsLoading(false);
    }
  };

  const updateEstimatedTime = useCallback(async () => {
    if (linuxSizeGb <= 0) return;
    try {
      const time = await calculateEstimatedTime(linuxSizeGb);
      setEstimatedTime(time);
    } catch {
      setEstimatedTime('');
    }
  }, [linuxSizeGb]);

  useEffect(() => {
    loadDisks();
  }, []);

  useEffect(() => {
    updateEstimatedTime();
  }, [updateEstimatedTime]);

  const handleDiskChange = (diskName: string) => {
    setSelectedDisk(diskName);
    const disk = disks.find((d) => d.name === diskName);
    if (disk) {
      const maxSize = Math.min(100, Math.floor(disk.free_space_gb * 0.5));
      const recommended = Math.max(40, Math.floor(disk.free_space_gb * 0.3));
      setLinuxSizeGb(Math.max(MIN_SIZE_GB, Math.min(recommended, maxSize)));
    }
  };

  const updateSizeFromPointer = useCallback(
    (clientX: number) => {
      if (!barRef.current || !selectedDiskInfo) return;
      const rect = barRef.current.getBoundingClientRect();
      const x = Math.max(0, Math.min(clientX - rect.left, rect.width));
      const windowsPx = rect.width * ((selectedDiskInfo.size_gb - selectedDiskInfo.free_space_gb) / selectedDiskInfo.size_gb);
      const altosPx = x - windowsPx;
      let newSize = Math.round((altosPx / rect.width) * selectedDiskInfo.size_gb);
      newSize = Math.max(MIN_SIZE_GB, Math.min(maxSizeGb, newSize));
      setLinuxSizeGb(newSize);
    },
    [maxSizeGb, selectedDiskInfo]
  );

  useEffect(() => {
    if (!isDragging) return;
    const handleMove = (e: PointerEvent) => updateSizeFromPointer(e.clientX);
    const handleUp = () => setIsDragging(false);
    window.addEventListener('pointermove', handleMove);
    window.addEventListener('pointerup', handleUp);
    return () => {
      window.removeEventListener('pointermove', handleMove);
      window.removeEventListener('pointerup', handleUp);
    };
  }, [isDragging, updateSizeFromPointer]);

  const handleContinue = async () => {
    if (!selectedDisk) return;

    if (encrypt && luksPassword.length < 8) {
      setError('Encryption password must be at least 8 characters.');
      return;
    }

    setIsSaving(true);
    setError(null);

    try {
      await setDiskConfig(
        selectedDisk,
        linuxSizeGb,
        filesystem,
        encrypt,
        encrypt ? luksPassword : undefined
      );
      const disk = disks.find((d) => d.name === selectedDisk);
      await writeTestState(TEST_STATE_PATH, {
        screen: 'disk',
        selectedDisk,
        linuxSizeGb,
        freeSpaceGb: disk?.free_space_gb ?? 0,
        timestamp: Date.now(),
      });
      onNext();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save disk configuration');
      setIsSaving(false);
    }
  };

  const handleContinueRef = useRef(handleContinue);
  handleContinueRef.current = handleContinue;

  useEffect(() => {
    if (!autoplay || isLoading || !selectedDisk || isSaving) return;
    const t = setTimeout(() => {
      handleContinueRef.current();
    }, 800);
    return () => clearTimeout(t);
  }, [autoplay, isLoading, selectedDisk, isSaving]);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-altos-text">Disk Selection</h2>
        <p className="text-sm text-altos-text-secondary">
          Choose which disk to install Linux on and how much space to allocate.
        </p>
      </div>

      {/* Error Message */}
      <AnimatePresence>
        {error && (
          <motion.div
            initial={{ opacity: 0, y: 4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4"
          >
            <div className="flex items-center gap-2 mb-1">
              <AlertTriangle className="w-5 h-5 text-altos-danger" />
              <span className="font-medium text-altos-text text-sm">Error</span>
            </div>
            <p className="text-sm text-altos-text-secondary">{error}</p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Disk Selection */}
      <div className="space-y-3">
        <label className="block text-sm font-medium text-altos-text">Select Disk</label>
        {isLoading ? (
          <div className="flex items-center justify-center p-8 bg-[#1a1d21] border border-altos-border rounded-xl">
            <div className="w-8 h-8 border-4 border-altos-border border-t-altos-blue rounded-full animate-spin" />
          </div>
        ) : (
          <div className="space-y-3">
            {disks.map((disk) => (
              <button
                key={disk.name}
                onClick={() => handleDiskChange(disk.name)}
                className={`w-full p-4 rounded-xl border text-left transition-all duration-150 ${
                  selectedDisk === disk.name
                    ? 'border-altos-blue bg-altos-blue-glow'
                    : 'border-altos-border hover:border-[#3a3f47]'
                }`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div
                      className={`w-10 h-10 rounded-lg flex items-center justify-center transition-colors duration-150 ${
                        selectedDisk === disk.name ? 'bg-altos-blue' : 'bg-[#1a1d21]'
                      }`}
                    >
                      <HardDrive
                        className={`w-5 h-5 transition-colors duration-150 ${
                          selectedDisk === disk.name ? 'text-white' : 'text-altos-text-secondary'
                        }`}
                      />
                    </div>
                    <div>
                      <p className="font-medium text-altos-text text-sm">{disk.name}</p>
                      <p className="text-xs text-altos-text-secondary">
                        Total: {formatSize(disk.size_gb)} &middot; Free: {formatSize(disk.free_space_gb)}
                      </p>
                    </div>
                  </div>
                  {selectedDisk === disk.name && (
                    <CheckCircle className="w-5 h-5 text-altos-blue flex-shrink-0" />
                  )}
                </div>

                {/* Mini usage bar */}
                <div className="mt-3">
                  <div className="h-1.5 bg-[#1e2127] rounded-full overflow-hidden">
                    <div
                      className="h-full bg-altos-blue rounded-full transition-all duration-300"
                      style={{
                        width: `${((disk.size_gb - disk.free_space_gb) / disk.size_gb) * 100}%`,
                      }}
                    />
                  </div>
                  <div className="flex justify-between mt-1.5 text-xs text-altos-text-secondary">
                    <span>Used: {formatSize(disk.size_gb - disk.free_space_gb)}</span>
                    <span>Free: {formatSize(disk.free_space_gb)}</span>
                  </div>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Visual Disk Map */}
      <AnimatePresence>
        {selectedDiskInfo && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            className="space-y-4"
          >
            <div className="bg-[#1a1d21] border border-altos-border rounded-xl p-5 space-y-5">
              {/* Bar */}
              <div
                ref={barRef}
                className="relative h-16 rounded-full overflow-hidden flex select-none shadow-inner"
                style={{ boxShadow: 'inset 0 2px 8px rgba(0,0,0,0.4)' }}
              >
                {/* Windows */}
                <div
                  className="h-full bg-blue-600 flex flex-col items-center justify-center gap-0.5 relative transition-all duration-200 ease-out"
                  style={{ width: `${windowsPct}%` }}
                >
                  {windowsPct > 12 && (
                    <>
                      <Monitor className="w-4 h-4 text-blue-100 shrink-0" />
                      <span className="text-[10px] font-semibold text-blue-100 whitespace-nowrap">Windows</span>
                      <span className="text-[10px] text-blue-200/80 whitespace-nowrap">{formatSize(windowsSizeGb)}</span>
                    </>
                  )}
                </div>

                {/* AltOS */}
                <div
                  className="h-full bg-emerald-500 flex flex-col items-center justify-center gap-0.5 relative transition-all duration-200 ease-out"
                  style={{ width: `${altosPct}%` }}
                >
                  {altosPct > 12 && (
                    <>
                      <Leaf className="w-4 h-4 text-emerald-100 shrink-0" />
                      <span className="text-[10px] font-semibold text-emerald-100 whitespace-nowrap">AltOS</span>
                      <span className="text-[10px] text-emerald-200/80 whitespace-nowrap">{formatSize(linuxSizeGb)}</span>
                    </>
                  )}
                </div>

                {/* Free */}
                <div
                  className="h-full bg-slate-700 flex flex-col items-center justify-center gap-0.5 transition-all duration-200 ease-out"
                  style={{ width: `${freePct}%` }}
                >
                  {freePct > 10 && (
                    <>
                      <span className="text-[10px] font-semibold text-slate-400 whitespace-nowrap">Free</span>
                      <span className="text-[10px] text-slate-500 whitespace-nowrap">{formatSize(freeSizeGb)}</span>
                    </>
                  )}
                </div>

                {/* Draggable handle */}
                <motion.div
                  className="absolute top-0 bottom-0 w-8 -ml-4 cursor-ew-resize flex items-center justify-center z-10"
                  style={{ left: `${windowsPct + altosPct}%` }}
                  whileHover={{ scale: 1.15 }}
                  whileTap={{ scale: 0.9 }}
                  onPointerDown={(e) => {
                    e.preventDefault();
                    setIsDragging(true);
                  }}
                >
                  <div
                    className={`w-1.5 h-10 rounded-full transition-all duration-200 ${
                      isDragging
                        ? 'bg-white shadow-[0_0_12px_rgba(52,211,153,0.6)]'
                        : 'bg-white/90 shadow-lg group-hover:shadow-[0_0_12px_rgba(52,211,153,0.4)]'
                    }`}
                  />
                </motion.div>
              </div>

              {/* Friendly sentence */}
              <p className="text-sm text-altos-text-secondary text-center">
                <span className="text-altos-text font-medium">{formatSize(linuxSizeGb)}</span> gives you room for
                apps, games, and files. You'll still have{' '}
                <span className="text-altos-text font-medium">{formatSize(selectedDiskInfo.size_gb - linuxSizeGb)}</span>{' '}
                for Windows.
              </p>

              {/* Info */}
              <div className="bg-altos-card border border-altos-border rounded-lg p-4 flex items-start gap-3">
                <Info className="w-5 h-5 text-altos-blue flex-shrink-0 mt-0.5" />
                <div className="text-sm text-altos-text-secondary">
                  <p className="font-medium text-altos-text mb-1">Partition Layout</p>
                  <p>
                    AltOS will be installed in a new partition carved from your free space. Your Windows data stays
                    untouched.
                  </p>
                </div>
              </div>

              {/* Estimated Time */}
              {estimatedTime && (
                <div className="flex items-center gap-2 text-sm text-altos-text-secondary">
                  <Clock className="w-4 h-4" />
                  <span>
                    Estimated time: <span className="text-altos-text font-medium">{estimatedTime}</span>
                  </span>
                </div>
              )}

              {/* Advanced options toggle */}
              <button
                onClick={() => setShowAdvanced((s) => !s)}
                className="flex items-center gap-1.5 text-xs font-medium text-altos-text-secondary hover:text-altos-text transition-colors"
              >
                <span>Advanced options</span>
                <motion.span animate={{ rotate: showAdvanced ? 180 : 0 }} transition={{ duration: 0.2 }}>
                  <ChevronDown className="w-3.5 h-3.5" />
                </motion.span>
              </button>

              {/* Advanced panel */}
              <AnimatePresence>
                {showAdvanced && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: 'auto' }}
                    exit={{ opacity: 0, height: 0 }}
                    transition={{ duration: 0.25, ease: 'easeInOut' }}
                    className="overflow-hidden"
                  >
                    <div className="space-y-5 pt-2">
                      {/* Numeric slider */}
                      <div className="space-y-3">
                        <div className="flex items-center justify-between">
                          <label className="text-sm font-medium text-altos-text">AltOS Partition Size</label>
                          <span className="text-xl font-semibold text-emerald-400">{linuxSizeGb} GB</span>
                        </div>
                        <input
                          type="range"
                          min={MIN_SIZE_GB}
                          max={maxSizeGb}
                          value={linuxSizeGb}
                          onChange={(e) => setLinuxSizeGb(Number(e.target.value))}
                          className="w-full accent-emerald-500"
                        />
                        <div className="flex justify-between text-xs text-altos-text-secondary">
                          <span>Min: {MIN_SIZE_GB} GB</span>
                          <span>Max: {maxSizeGb} GB (50% of free space)</span>
                        </div>
                      </div>

                      {/* Filesystem selector */}
                      <div className="space-y-2">
                        <label className="text-sm font-medium text-altos-text">Filesystem</label>
                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                          {FILESYSTEMS.map((fs) => (
                            <button
                              key={fs.value}
                              onClick={() => setFilesystem(fs.value)}
                              className={`p-3 rounded-xl border text-left transition-all duration-150 ${
                                filesystem === fs.value
                                  ? 'border-emerald-500/50 bg-emerald-500/10'
                                  : 'border-altos-border hover:border-[#3a3f47]'
                              }`}
                            >
                              <p
                                className={`text-sm font-medium ${
                                  filesystem === fs.value ? 'text-emerald-400' : 'text-altos-text'
                                }`}
                              >
                                {fs.value}
                              </p>
                              <p className="text-[11px] text-altos-text-secondary mt-0.5">{fs.desc}</p>
                            </button>
                          ))}
                        </div>
                      </div>

                      {/* Encryption toggle */}
                      <div className="space-y-3">
                        <button
                          onClick={() => setEncrypt((e) => !e)}
                          className={`w-full flex items-center gap-3 p-3 rounded-xl border transition-all duration-150 ${
                            encrypt
                              ? 'border-emerald-500/50 bg-emerald-500/10'
                              : 'border-altos-border hover:border-[#3a3f47]'
                          }`}
                        >
                          <div
                            className={`w-10 h-10 rounded-lg flex items-center justify-center ${
                              encrypt ? 'bg-emerald-500/20 text-emerald-400' : 'bg-[#1e2127] text-altos-text-secondary'
                            }`}
                          >
                            <Lock className="w-5 h-5" />
                          </div>
                          <div className="text-left flex-1">
                            <p className={`text-sm font-medium ${encrypt ? 'text-emerald-400' : 'text-altos-text'}`}>
                              Encrypt my AltOS
                            </p>
                            <p className="text-xs text-altos-text-secondary">Protect your data with LUKS encryption</p>
                          </div>
                          <div
                            className={`w-10 h-6 rounded-full p-1 transition-colors duration-200 ${
                              encrypt ? 'bg-emerald-500' : 'bg-slate-700'
                            }`}
                          >
                            <motion.div
                              animate={{ x: encrypt ? 16 : 0 }}
                              transition={{ type: 'spring', stiffness: 500, damping: 30 }}
                              className="w-4 h-4 rounded-full bg-white shadow-sm"
                            />
                          </div>
                        </button>

                        <AnimatePresence>
                          {encrypt && (
                            <motion.div
                              initial={{ opacity: 0, height: 0 }}
                              animate={{ opacity: 1, height: 'auto' }}
                              exit={{ opacity: 0, height: 0 }}
                              className="overflow-hidden"
                            >
                              <div className="space-y-2">
                                <label className="text-xs font-medium text-altos-text-secondary">
                                  LUKS passphrase
                                </label>
                                <input
                                  type="password"
                                  value={luksPassword}
                                  onChange={(e) => setLuksPassword(e.target.value)}
                                  placeholder="At least 8 characters"
                                  className="w-full px-4 py-2.5 rounded-xl bg-[#1e2127] border border-altos-border text-sm text-altos-text placeholder-altos-text-secondary focus:outline-none focus:border-emerald-500/50 transition-colors"
                                />
                                <p className="text-xs text-altos-text-secondary">
                                  You'll need this passphrase every time you boot into AltOS.
                                </p>
                              </div>
                            </motion.div>
                          )}
                        </AnimatePresence>
                      </div>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Navigation Buttons */}
      <div className="flex justify-between pt-2">
        <button
          onClick={onBack}
          disabled={isSaving}
          className="flex items-center gap-2 px-5 py-2.5 rounded-lg font-medium text-altos-text-secondary hover:text-altos-text hover:bg-[#1a1d21] transition-colors duration-150 disabled:opacity-50"
        >
          <ArrowLeft className="w-5 h-5" />
          <span>Back</span>
        </button>

        <button
          onClick={handleContinue}
          disabled={!selectedDisk || isLoading || isSaving}
          className={`flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white transition-colors duration-150 ${
            selectedDisk && !isLoading && !isSaving
              ? 'bg-altos-blue hover:bg-altos-blue-hover'
              : 'bg-[#3a3f47] cursor-not-allowed text-altos-text-secondary'
          }`}
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

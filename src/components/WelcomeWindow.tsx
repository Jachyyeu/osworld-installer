import { useState } from 'react';
import { Monitor, HardDrive, ArrowRight, Shield, Info } from 'lucide-react';
import { setInstallType } from '../lib/tauri';
import type { InstallType } from '../types';

interface WelcomeWindowProps {
  onSelect: (type: InstallType) => void;
}

export default function WelcomeWindow({ onSelect }: WelcomeWindowProps) {
  const [selectedType, setSelectedType] = useState<InstallType | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleContinue = async () => {
    if (!selectedType) return;

    setIsLoading(true);
    setError(null);

    try {
      await setInstallType(selectedType);
      onSelect(selectedType);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to set install type');
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Welcome Message */}
      <div className="text-center space-y-3">
        <div className="w-16 h-16 bg-altos-blue/10 rounded-2xl flex items-center justify-center mx-auto mb-4">
          <Monitor className="w-8 h-8 text-altos-blue" />
        </div>
        <h2 className="text-xl font-semibold text-altos-text">Welcome to AltOS</h2>
        <p className="text-base text-altos-text-secondary">
          Install Linux alongside Windows or replace it entirely
        </p>
      </div>

      {/* Info Box */}
      <div className="bg-[#1a1d21] border border-altos-border rounded-lg p-4 flex items-start gap-3">
        <Info className="w-5 h-5 text-altos-blue flex-shrink-0 mt-0.5" />
        <div className="text-sm text-altos-text-secondary">
          <p className="font-medium text-altos-text mb-1">Before you begin</p>
          <ul className="list-disc list-inside space-y-1">
            <li>Back up your important data</li>
            <li>Ensure your device is plugged in</li>
            <li>Have at least 20GB of free disk space</li>
          </ul>
        </div>
      </div>

      {/* Installation Options */}
      <div className="grid gap-4">
        {/* Dual Boot Option */}
        <button
          onClick={() => setSelectedType('dualboot')}
          className={`
            relative p-5 rounded-xl border text-left transition-all duration-150
            ${selectedType === 'dualboot'
              ? 'border-altos-blue bg-altos-blue-glow'
              : 'border-altos-border hover:border-[#3a3f47]'
            }
          `}
        >
          <div className="flex items-start gap-4">
            <div className={`
              w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 transition-colors duration-150
              ${selectedType === 'dualboot' ? 'bg-altos-blue' : 'bg-[#1a1d21]'}
            `}>
              <HardDrive className={`
                w-5 h-5 transition-colors duration-150
                ${selectedType === 'dualboot' ? 'text-white' : 'text-altos-text-secondary'}
              `} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between mb-1">
                <h3 className="text-base font-medium text-altos-text">Dual Boot</h3>
                {selectedType === 'dualboot' && (
                  <div className="w-5 h-5 rounded-full bg-altos-blue flex items-center justify-center flex-shrink-0">
                    <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                )}
              </div>
              <p className="text-sm text-altos-text-secondary mb-2">
                Keep Windows and install Linux alongside it. Choose which OS to boot at startup.
              </p>
              <div className="flex items-center gap-2 text-sm text-altos-success">
                <Shield className="w-4 h-4" />
                <span>Recommended for beginners</span>
              </div>
            </div>
          </div>
        </button>

        {/* Replace Windows Option */}
        <button
          onClick={() => setSelectedType('replace')}
          className={`
            relative p-5 rounded-xl border text-left transition-all duration-150
            ${selectedType === 'replace'
              ? 'border-altos-blue bg-altos-blue-glow'
              : 'border-altos-border hover:border-[#3a3f47]'
            }
          `}
        >
          <div className="flex items-start gap-4">
            <div className={`
              w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 transition-colors duration-150
              ${selectedType === 'replace' ? 'bg-altos-blue' : 'bg-[#1a1d21]'}
            `}>
              <Monitor className={`
                w-5 h-5 transition-colors duration-150
                ${selectedType === 'replace' ? 'text-white' : 'text-altos-text-secondary'}
              `} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between mb-1">
                <h3 className="text-base font-medium text-altos-text">Replace Windows</h3>
                {selectedType === 'replace' && (
                  <div className="w-5 h-5 rounded-full bg-altos-blue flex items-center justify-center flex-shrink-0">
                    <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                )}
              </div>
              <p className="text-sm text-altos-text-secondary mb-2">
                Completely replace Windows with Linux. All data will be erased.
              </p>
              <div className="flex items-center gap-2 text-sm text-altos-warning">
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <span>All data will be lost</span>
              </div>
            </div>
          </div>
        </button>
      </div>

      {/* Error Message */}
      {error && (
        <div className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4 text-sm text-altos-text">
          {error}
        </div>
      )}

      {/* Continue Button */}
      <div className="flex justify-end pt-2">
        <button
          onClick={handleContinue}
          disabled={!selectedType || isLoading}
          className={`
            flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
            transition-colors duration-150
            ${selectedType && !isLoading
              ? 'bg-altos-blue hover:bg-altos-blue-hover'
              : 'bg-[#3a3f47] cursor-not-allowed text-altos-text-secondary'
            }
          `}
        >
          {isLoading ? (
            <>
              <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              <span>Loading...</span>
            </>
          ) : (
            <>
              <span>Get Started</span>
              <ArrowRight className="w-5 h-5" />
            </>
          )}
        </button>
      </div>
    </div>
  );
}

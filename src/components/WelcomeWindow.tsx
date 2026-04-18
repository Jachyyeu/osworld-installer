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
      <div className="text-center space-y-2">
        <h2 className="text-3xl font-bold text-slate-800">Welcome to OSWorld</h2>
        <p className="text-slate-600 text-lg">
          Install Linux alongside Windows or replace it
        </p>
      </div>

      {/* Info Box */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 flex items-start gap-3">
        <Info className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
        <div className="text-sm text-blue-800">
          <p className="font-medium mb-1">Before you begin:</p>
          <ul className="list-disc list-inside space-y-1">
            <li>Back up your important data</li>
            <li>Ensure your device is plugged in</li>
            <li>Have at least 20GB of free disk space</li>
          </ul>
        </div>
      </div>

      {/* Installation Options */}
      <div className="grid md:grid-cols-2 gap-4">
        {/* Dual Boot Option */}
        <button
          onClick={() => setSelectedType('dualboot')}
          className={`
            relative p-6 rounded-xl border-2 text-left transition-all duration-200
            ${selectedType === 'dualboot'
              ? 'border-primary-500 bg-primary-50 shadow-lg'
              : 'border-slate-200 hover:border-primary-300 hover:bg-slate-50'
            }
          `}
        >
          <div className="flex items-start justify-between mb-4">
            <div className={`
              w-12 h-12 rounded-xl flex items-center justify-center
              ${selectedType === 'dualboot' ? 'bg-primary-500' : 'bg-slate-100'}
            `}>
              <HardDrive className={`
                w-6 h-6
                ${selectedType === 'dualboot' ? 'text-white' : 'text-slate-600'}
              `} />
            </div>
            {selectedType === 'dualboot' && (
              <div className="w-6 h-6 rounded-full bg-primary-500 flex items-center justify-center">
                <svg className="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                </svg>
              </div>
            )}
          </div>
          <h3 className="text-lg font-semibold text-slate-800 mb-2">
            Dual Boot
          </h3>
          <p className="text-sm text-slate-600 mb-3">
            Keep Windows and install Linux alongside it. Choose which OS to boot at startup.
          </p>
          <div className="flex items-center gap-2 text-sm text-green-600">
            <Shield className="w-4 h-4" />
            <span>Recommended for beginners</span>
          </div>
        </button>

        {/* Replace Windows Option */}
        <button
          onClick={() => setSelectedType('replace')}
          className={`
            relative p-6 rounded-xl border-2 text-left transition-all duration-200
            ${selectedType === 'replace'
              ? 'border-primary-500 bg-primary-50 shadow-lg'
              : 'border-slate-200 hover:border-primary-300 hover:bg-slate-50'
            }
          `}
        >
          <div className="flex items-start justify-between mb-4">
            <div className={`
              w-12 h-12 rounded-xl flex items-center justify-center
              ${selectedType === 'replace' ? 'bg-primary-500' : 'bg-slate-100'}
            `}>
              <Monitor className={`
                w-6 h-6
                ${selectedType === 'replace' ? 'text-white' : 'text-slate-600'}
              `} />
            </div>
            {selectedType === 'replace' && (
              <div className="w-6 h-6 rounded-full bg-primary-500 flex items-center justify-center">
                <svg className="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                </svg>
              </div>
            )}
          </div>
          <h3 className="text-lg font-semibold text-slate-800 mb-2">
            Replace Windows
          </h3>
          <p className="text-sm text-slate-600 mb-3">
            Completely replace Windows with Linux. All data will be erased.
          </p>
          <div className="flex items-center gap-2 text-sm text-amber-600">
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <span>All data will be lost</span>
          </div>
        </button>
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700 text-sm">
          {error}
        </div>
      )}

      {/* Continue Button */}
      <div className="flex justify-end pt-4">
        <button
          onClick={handleContinue}
          disabled={!selectedType || isLoading}
          className={`
            flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
            transition-all duration-200
            ${selectedType && !isLoading
              ? 'bg-primary-600 hover:bg-primary-700 shadow-lg hover:shadow-xl'
              : 'bg-slate-300 cursor-not-allowed'
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
              <span>Continue</span>
              <ArrowRight className="w-5 h-5" />
            </>
          )}
        </button>
      </div>
    </div>
  );
}

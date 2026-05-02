import { useState } from 'react';
import type { InstallType, InstallConfig } from './types';
import WelcomeWindow from './components/WelcomeWindow';
import SystemCheckWindow from './components/SystemCheckWindow';
import DiskSelectionWindow from './components/DiskSelectionWindow';
import UserSetupWindow from './components/UserSetupWindow';
import EditionSelectionWindow from './components/EditionSelectionWindow';
import InstallationProgressWindow from './components/InstallationProgressWindow';

type WindowStep = 'welcome' | 'systemcheck' | 'diskselection' | 'usersetup' | 'edition' | 'progress';

function App() {
  const [currentStep, setCurrentStep] = useState<WindowStep>('welcome');
  const [installType, setInstallTypeState] = useState<InstallType | null>(null);
  const [, setConfig] = useState<InstallConfig>({});

  const handleInstallTypeSelect = (type: InstallType) => {
    setInstallTypeState(type);
    setConfig(prev => ({ ...prev, install_type: type }));
    setCurrentStep('systemcheck');
  };

  const handleSystemCheckComplete = () => {
    if (installType === 'dualboot') {
      setCurrentStep('diskselection');
    } else {
      setCurrentStep('usersetup');
    }
  };

  const handleDiskSelectionComplete = () => {
    setCurrentStep('usersetup');
  };

  const handleUserSetupComplete = () => {
    setCurrentStep('edition');
  };

  const handleEditionComplete = () => {
    setCurrentStep('progress');
  };

  const handleBack = (step: WindowStep) => {
    setCurrentStep(step);
  };

  const renderCurrentWindow = () => {
    switch (currentStep) {
      case 'welcome':
        return (
          <WelcomeWindow 
            onSelect={handleInstallTypeSelect} 
          />
        );
      
      case 'systemcheck':
        return (
          <SystemCheckWindow 
            onNext={handleSystemCheckComplete}
            onBack={() => handleBack('welcome')}
          />
        );
      
      case 'diskselection':
        return (
          <DiskSelectionWindow 
            onNext={handleDiskSelectionComplete}
            onBack={() => handleBack('systemcheck')}
          />
        );
      
      case 'usersetup':
        return (
          <UserSetupWindow 
            onNext={handleUserSetupComplete}
            onBack={() => handleBack(installType === 'dualboot' ? 'diskselection' : 'systemcheck')}
          />
        );
      
      case 'edition':
        return (
          <EditionSelectionWindow 
            onNext={handleEditionComplete}
            onBack={() => handleBack('usersetup')}
          />
        );
      
      case 'progress':
        return (
          <InstallationProgressWindow />
        );
      
      default:
        return <WelcomeWindow onSelect={handleInstallTypeSelect} />;
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex items-center justify-center p-4">
      <div className="w-full max-w-4xl bg-white rounded-2xl shadow-2xl overflow-hidden animate-fade-in">
        {/* Header */}
        <div className="bg-gradient-to-r from-primary-600 to-primary-700 px-8 py-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-white/20 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
              </svg>
            </div>
            <div>
              <h1 className="text-2xl font-bold text-white">OSWorld Installer</h1>
              <p className="text-primary-100 text-sm">Linux Distribution Installer</p>
            </div>
          </div>
        </div>

        {/* Progress Indicator */}
        {currentStep !== 'welcome' && currentStep !== 'progress' && (
          <div className="bg-slate-50 px-8 py-4 border-b border-slate-200">
            <div className="flex items-center justify-between">
              {[
                { id: 'systemcheck', label: 'System Check' },
                ...(installType === 'dualboot' ? [{ id: 'diskselection', label: 'Disk Selection' }] : []),
                { id: 'usersetup', label: 'User Setup' },
                { id: 'edition', label: 'Edition' },
              ].map((step, index, arr) => (
                <div key={step.id} className="flex items-center">
                  <div className={`
                    w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium
                    ${currentStep === step.id 
                      ? 'bg-primary-600 text-white' 
                      : arr.findIndex(s => s.id === currentStep) > index
                        ? 'bg-green-500 text-white'
                        : 'bg-slate-200 text-slate-500'
                    }
                  `}>
                    {arr.findIndex(s => s.id === currentStep) > index ? (
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                      </svg>
                    ) : (
                      index + 1
                    )}
                  </div>
                  <span className={`
                    ml-2 text-sm font-medium hidden sm:block
                    ${currentStep === step.id ? 'text-primary-700' : 'text-slate-500'}
                  `}>
                    {step.label}
                  </span>
                  {index < arr.length - 1 && (
                    <div className="w-8 sm:w-12 h-0.5 bg-slate-200 mx-2 sm:mx-4" />
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Content */}
        <div className="p-8">
          {renderCurrentWindow()}
        </div>
      </div>
    </div>
  );
}

export default App;

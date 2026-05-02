import { useState } from 'react';
import { 
  Home, 
  Gamepad2, 
  Palette, 
  Check,
  ArrowRight, 
  ArrowLeft,
  Star,
  Monitor
} from 'lucide-react';
import { setEdition } from '../lib/tauri';
import type { Edition } from '../types';

interface EditionSelectionWindowProps {
  onNext: () => void;
  onBack: () => void;
}

interface EditionOption {
  id: Edition;
  name: string;
  price: string;
  description: string;
  icon: React.ReactNode;
  features: string[];
  color: string;
  recommended?: boolean;
}

const EDITIONS: EditionOption[] = [
  {
    id: 'home',
    name: 'Home',
    price: 'Free',
    description: 'Essential features for everyday computing, web browsing, and productivity.',
    icon: <Home className="w-6 h-6" />,
    features: [
      'Web browser and email client',
      'Office suite (LibreOffice)',
      'Media player',
      'Basic system utilities',
      'Community support'
    ],
    color: 'from-blue-500 to-blue-600',
  },
  {
    id: 'gaming',
    name: 'Gaming',
    price: '$9.99',
    description: 'Optimized for gaming with latest drivers, Steam pre-installed, and performance tweaks.',
    icon: <Gamepad2 className="w-6 h-6" />,
    features: [
      'Latest NVIDIA/AMD drivers',
      'Steam, Lutris, Heroic Launcher',
      'Proton GE for Windows games',
      'Gaming performance tweaks',
      'Discord and communication tools',
      'Priority support'
    ],
    color: 'from-purple-500 to-purple-600',
    recommended: true,
  },
  {
    id: 'create',
    name: 'Create',
    price: '$14.99',
    description: 'Professional tools for content creation, video editing, and development workflows.',
    icon: <Palette className="w-6 h-6" />,
    features: [
      'All Gaming edition features',
      'Blender, Kdenlive, GIMP',
      'VS Code, Docker, Node.js',
      'Audio production tools',
      'Design and graphics software',
      'Premium support'
    ],
    color: 'from-amber-500 to-amber-600',
  },
];

export default function EditionSelectionWindow({ onNext, onBack }: EditionSelectionWindowProps) {
  const [selectedEdition, setSelectedEdition] = useState<Edition | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleContinue = async () => {
    if (!selectedEdition) return;
    
    setIsLoading(true);
    setError(null);
    
    try {
      await setEdition(selectedEdition);
      onNext();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save edition selection');
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-bold text-slate-800">Choose Your Edition</h2>
        <p className="text-slate-600">
          Select the edition that best fits your needs.
        </p>
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
          {error}
        </div>
      )}

      {/* Edition Cards */}
      <div className="grid md:grid-cols-3 gap-4">
        {EDITIONS.map((edition) => (
          <button
            key={edition.id}
            onClick={() => setSelectedEdition(edition.id)}
            className={`
              relative p-5 rounded-xl border-2 text-left transition-all duration-200 flex flex-col
              ${selectedEdition === edition.id
                ? 'border-primary-500 bg-primary-50 shadow-lg scale-[1.02]'
                : 'border-slate-200 hover:border-primary-300 hover:bg-slate-50 hover:shadow-md'
              }
            `}
          >
            {/* Recommended Badge */}
            {edition.recommended && (
              <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                <span className="bg-gradient-to-r from-amber-400 to-amber-500 text-white text-xs font-bold px-3 py-1 rounded-full shadow-md flex items-center gap-1">
                  <Star className="w-3 h-3" />
                  RECOMMENDED
                </span>
              </div>
            )}

            {/* Icon & Name */}
            <div className="flex items-center gap-3 mb-3">
              <div className={`
                w-12 h-12 rounded-xl bg-gradient-to-br ${edition.color} 
                flex items-center justify-center text-white shadow-md
              `}>
                {edition.icon}
              </div>
              <div>
                <h3 className="font-bold text-slate-800">{edition.name}</h3>
                <p className={`
                  text-lg font-bold
                  ${edition.price === 'Free' ? 'text-green-600' : 'text-primary-600'}
                `}>
                  {edition.price}
                </p>
              </div>
            </div>

            {/* Description */}
            <p className="text-sm text-slate-600 mb-4 flex-grow">
              {edition.description}
            </p>

            {/* Features */}
            <div className="space-y-2 mb-4">
              {edition.features.slice(0, 4).map((feature, idx) => (
                <div key={idx} className="flex items-start gap-2 text-sm">
                  <Check className="w-4 h-4 text-green-500 flex-shrink-0 mt-0.5" />
                  <span className="text-slate-600">{feature}</span>
                </div>
              ))}
              {edition.features.length > 4 && (
                <p className="text-sm text-slate-400 pl-6">
                  +{edition.features.length - 4} more
                </p>
              )}
            </div>

            {/* Selection Indicator */}
            <div className={`
              mt-auto pt-4 border-t border-slate-200
              ${selectedEdition === edition.id ? 'border-primary-200' : ''}
            `}>
              <div className={`
                w-full py-2 rounded-lg font-semibold text-center transition-colors
                ${selectedEdition === edition.id
                  ? 'bg-primary-600 text-white'
                  : 'bg-slate-100 text-slate-600'
                }
              `}>
                {selectedEdition === edition.id ? 'Selected' : 'Select'}
              </div>
            </div>
          </button>
        ))}
      </div>

      {/* Comparison Table */}
      <div className="bg-slate-50 rounded-lg p-4">
        <h4 className="font-semibold text-slate-800 mb-3 flex items-center gap-2">
          <Monitor className="w-5 h-5 text-primary-600" />
          Quick Comparison
        </h4>
        <div className="grid grid-cols-4 gap-4 text-sm">
          <div className="font-medium text-slate-500">Feature</div>
          <div className="font-medium text-slate-700 text-center">Home</div>
          <div className="font-medium text-purple-700 text-center">Gaming</div>
          <div className="font-medium text-amber-700 text-center">Create</div>
          
          <div className="text-slate-600">Web & Email</div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          
          <div className="text-slate-600">Office Suite</div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          
          <div className="text-slate-600">Gaming Ready</div>
          <div className="text-center text-slate-400">-</div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          
          <div className="text-slate-600">Dev Tools</div>
          <div className="text-center text-slate-400">-</div>
          <div className="text-center text-slate-400">-</div>
          <div className="text-center"><Check className="w-5 h-5 text-green-500 mx-auto" /></div>
          
          <div className="text-slate-600">Support</div>
          <div className="text-center text-slate-500">Community</div>
          <div className="text-center text-purple-600 font-medium">Priority</div>
          <div className="text-center text-amber-600 font-medium">Premium</div>
        </div>
      </div>

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
          onClick={handleContinue}
          disabled={!selectedEdition || isLoading}
          className={`
            flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
            transition-all duration-200
            ${selectedEdition && !isLoading
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

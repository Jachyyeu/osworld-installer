import { useState } from 'react';
import { 
  User, 
  Monitor, 
  Lock, 
  Eye, 
  EyeOff,
  ArrowRight, 
  ArrowLeft,
  CheckCircle,
  AlertTriangle,
  Info
} from 'lucide-react';
import { setUserConfig } from '../lib/tauri';

interface UserSetupWindowProps {
  onNext: () => void;
  onBack: () => void;
}

interface ValidationError {
  field: string;
  message: string;
}

export default function UserSetupWindow({ onNext, onBack }: UserSetupWindowProps) {
  const [username, setUsername] = useState('');
  const [computerName, setComputerName] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<ValidationError[]>([]);

  const validateForm = (): ValidationError[] => {
    const newErrors: ValidationError[] = [];

    // Username validation (lowercase only, at least 3 characters)
    if (username !== username.toLowerCase()) {
      newErrors.push({ field: 'username', message: 'Username must be lowercase only' });
    }
    if (username.length < 3) {
      newErrors.push({ field: 'username', message: 'Username must be at least 3 characters' });
    }
    if (!/^[a-z][a-z0-9_-]*$/.test(username)) {
      newErrors.push({ field: 'username', message: 'Username must start with a letter and contain only letters, numbers, underscores, or hyphens' });
    }

    // Computer name validation
    if (computerName.length < 3) {
      newErrors.push({ field: 'computerName', message: 'Computer name must be at least 3 characters' });
    }

    // Password validation (8+ characters)
    if (password.length < 8) {
      newErrors.push({ field: 'password', message: 'Password must be at least 8 characters' });
    }

    // Confirm password
    if (password !== confirmPassword) {
      newErrors.push({ field: 'confirmPassword', message: 'Passwords do not match' });
    }

    return newErrors;
  };

  const getFieldError = (field: string): string | undefined => {
    return errors.find(e => e.field === field)?.message;
  };

  const handleContinue = async () => {
    const validationErrors = validateForm();
    setErrors(validationErrors);

    if (validationErrors.length > 0) {
      return;
    }

    setIsLoading(true);

    try {
      await setUserConfig(username, computerName, password, confirmPassword);
      onNext();
    } catch (err) {
      setErrors([{ 
        field: 'general', 
        message: err instanceof Error ? err.message : 'Failed to save user configuration' 
      }]);
      setIsLoading(false);
    }
  };

  const getPasswordStrength = (pwd: string): { strength: number; label: string; color: string } => {
    let strength = 0;
    if (pwd.length >= 8) strength++;
    if (pwd.length >= 12) strength++;
    if (/[A-Z]/.test(pwd)) strength++;
    if (/[0-9]/.test(pwd)) strength++;
    if (/[^A-Za-z0-9]/.test(pwd)) strength++;

    const labels = ['Very Weak', 'Weak', 'Fair', 'Good', 'Strong', 'Very Strong'];
    const colors = ['bg-red-500', 'bg-red-400', 'bg-amber-400', 'bg-yellow-400', 'bg-green-400', 'bg-green-500'];

    return {
      strength,
      label: labels[strength] || 'Very Weak',
      color: colors[strength] || 'bg-red-500'
    };
  };

  const passwordStrength = getPasswordStrength(password);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-bold text-slate-800">User Setup</h2>
        <p className="text-slate-600">
          Create your user account for OSWorld Linux.
        </p>
      </div>

      {/* General Error */}
      {getFieldError('general') && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-5 h-5" />
            <span>{getFieldError('general')}</span>
          </div>
        </div>
      )}

      {/* Form */}
      <div className="space-y-4">
        {/* Username */}
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-slate-700">
            Username
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <User className="h-5 w-5 text-slate-400" />
            </div>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value.toLowerCase())}
              placeholder="e.g., john_doe"
              className={`
                w-full pl-10 pr-4 py-3 rounded-lg border-2 transition-colors
                ${getFieldError('username')
                  ? 'border-red-300 focus:border-red-500 focus:ring-red-200'
                  : 'border-slate-200 focus:border-primary-500 focus:ring-primary-200'
                }
                focus:outline-none focus:ring-4
              `}
            />
          </div>
          {getFieldError('username') ? (
            <p className="text-sm text-red-600 flex items-center gap-1">
              <AlertTriangle className="w-4 h-4" />
              {getFieldError('username')}
            </p>
          ) : (
            <p className="text-sm text-slate-500 flex items-center gap-1">
              <Info className="w-4 h-4" />
              Lowercase letters, numbers, underscores, and hyphens only
            </p>
          )}
        </div>

        {/* Computer Name */}
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-slate-700">
            Computer Name
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Monitor className="h-5 w-5 text-slate-400" />
            </div>
            <input
              type="text"
              value={computerName}
              onChange={(e) => setComputerName(e.target.value)}
              placeholder="e.g., My-Laptop"
              className={`
                w-full pl-10 pr-4 py-3 rounded-lg border-2 transition-colors
                ${getFieldError('computerName')
                  ? 'border-red-300 focus:border-red-500 focus:ring-red-200'
                  : 'border-slate-200 focus:border-primary-500 focus:ring-primary-200'
                }
                focus:outline-none focus:ring-4
              `}
            />
          </div>
          {getFieldError('computerName') && (
            <p className="text-sm text-red-600 flex items-center gap-1">
              <AlertTriangle className="w-4 h-4" />
              {getFieldError('computerName')}
            </p>
          )}
        </div>

        {/* Password */}
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-slate-700">
            Password
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Lock className="h-5 w-5 text-slate-400" />
            </div>
            <input
              type={showPassword ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter a strong password"
              className={`
                w-full pl-10 pr-12 py-3 rounded-lg border-2 transition-colors
                ${getFieldError('password')
                  ? 'border-red-300 focus:border-red-500 focus:ring-red-200'
                  : 'border-slate-200 focus:border-primary-500 focus:ring-primary-200'
                }
                focus:outline-none focus:ring-4
              `}
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 hover:text-slate-600"
            >
              {showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
            </button>
          </div>
          
          {/* Password Strength */}
          {password && (
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <div className="flex-1 h-2 bg-slate-200 rounded-full overflow-hidden">
                  <div 
                    className={`h-full ${passwordStrength.color} transition-all duration-300`}
                    style={{ width: `${(passwordStrength.strength / 5) * 100}%` }}
                  />
                </div>
                <span className="text-sm text-slate-600 min-w-[80px]">{passwordStrength.label}</span>
              </div>
            </div>
          )}
          
          {getFieldError('password') ? (
            <p className="text-sm text-red-600 flex items-center gap-1">
              <AlertTriangle className="w-4 h-4" />
              {getFieldError('password')}
            </p>
          ) : (
            <p className="text-sm text-slate-500">
              At least 8 characters recommended
            </p>
          )}
        </div>

        {/* Confirm Password */}
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-slate-700">
            Confirm Password
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <CheckCircle className="h-5 w-5 text-slate-400" />
            </div>
            <input
              type={showConfirmPassword ? 'text' : 'password'}
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              placeholder="Re-enter your password"
              className={`
                w-full pl-10 pr-12 py-3 rounded-lg border-2 transition-colors
                ${getFieldError('confirmPassword')
                  ? 'border-red-300 focus:border-red-500 focus:ring-red-200'
                  : confirmPassword && password === confirmPassword
                    ? 'border-green-300 focus:border-green-500 focus:ring-green-200'
                    : 'border-slate-200 focus:border-primary-500 focus:ring-primary-200'
                }
                focus:outline-none focus:ring-4
              `}
            />
            <button
              type="button"
              onClick={() => setShowConfirmPassword(!showConfirmPassword)}
              className="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 hover:text-slate-600"
            >
              {showConfirmPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
            </button>
          </div>
          {getFieldError('confirmPassword') && (
            <p className="text-sm text-red-600 flex items-center gap-1">
              <AlertTriangle className="w-4 h-4" />
              {getFieldError('confirmPassword')}
            </p>
          )}
          {confirmPassword && password === confirmPassword && !getFieldError('confirmPassword') && (
            <p className="text-sm text-green-600 flex items-center gap-1">
              <CheckCircle className="w-4 h-4" />
              Passwords match
            </p>
          )}
        </div>
      </div>

      {/* Info Box */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 flex items-start gap-3">
        <Info className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
        <div className="text-sm text-blue-800">
          <p className="font-medium mb-1">Account Information</p>
          <p>
            This account will have administrator privileges. You'll use this username and password to log in to your system.
          </p>
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
          disabled={isLoading || !username || !computerName || !password || !confirmPassword}
          className={`
            flex items-center gap-2 px-8 py-3 rounded-lg font-semibold text-white
            transition-all duration-200
            ${username && computerName && password && confirmPassword && !isLoading
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

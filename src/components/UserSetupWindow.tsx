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

    if (username !== username.toLowerCase()) {
      newErrors.push({ field: 'username', message: 'Username must be lowercase only' });
    }
    if (username.length < 3) {
      newErrors.push({ field: 'username', message: 'Username must be at least 3 characters' });
    }
    if (!/^[a-z][a-z0-9_-]*$/.test(username)) {
      newErrors.push({ field: 'username', message: 'Must start with a letter and contain only letters, numbers, underscores, or hyphens' });
    }

    if (computerName.length < 3) {
      newErrors.push({ field: 'computerName', message: 'Computer name must be at least 3 characters' });
    }

    if (password.length < 8) {
      newErrors.push({ field: 'password', message: 'Password must be at least 8 characters' });
    }

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
    const colors = ['bg-altos-danger', 'bg-altos-danger', 'bg-altos-warning', 'bg-altos-warning', 'bg-altos-success', 'bg-altos-success'];

    return {
      strength,
      label: labels[strength] || 'Very Weak',
      color: colors[strength] || 'bg-altos-danger'
    };
  };

  const passwordStrength = getPasswordStrength(password);

  const inputBaseClass = `
    w-full bg-[#1a1d21] border border-altos-border rounded-lg px-3 py-2.5 text-sm text-altos-text
    placeholder:text-altos-text-secondary/50
    focus:outline-none focus:border-altos-blue focus:ring-1 focus:ring-altos-blue
    transition-colors duration-150
  `;

  const inputErrorClass = `
    w-full bg-[#1a1d21] border border-altos-danger rounded-lg px-3 py-2.5 text-sm text-altos-text
    placeholder:text-altos-text-secondary/50
    focus:outline-none focus:border-altos-danger focus:ring-1 focus:ring-altos-danger
    transition-colors duration-150
  `;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-1">
        <h2 className="text-xl font-semibold text-altos-text">User Setup</h2>
        <p className="text-sm text-altos-text-secondary">
          Create your user account for AltOS Linux.
        </p>
      </div>

      {/* General Error */}
      {getFieldError('general') && (
        <div className="border-l-4 border-altos-danger bg-[#1a1d21] rounded-r-lg p-4">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-altos-danger" />
            <span className="text-sm text-altos-text">{getFieldError('general')}</span>
          </div>
        </div>
      )}

      {/* Form */}
      <div className="space-y-4">
        {/* Username */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-altos-text">
            Username
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <User className="h-4 w-4 text-altos-text-secondary" />
            </div>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value.toLowerCase())}
              placeholder="e.g. john_doe"
              className={`${getFieldError('username') ? inputErrorClass : inputBaseClass} pl-9`}
            />
          </div>
          {getFieldError('username') ? (
            <p className="text-xs text-altos-danger flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" />
              {getFieldError('username')}
            </p>
          ) : (
            <p className="text-xs text-altos-text-secondary flex items-center gap-1">
              <Info className="w-3 h-3" />
              Lowercase letters, numbers, underscores, and hyphens only
            </p>
          )}
        </div>

        {/* Computer Name */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-altos-text">
            Computer Name
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Monitor className="h-4 w-4 text-altos-text-secondary" />
            </div>
            <input
              type="text"
              value={computerName}
              onChange={(e) => setComputerName(e.target.value)}
              placeholder="e.g. My-Laptop"
              className={`${getFieldError('computerName') ? inputErrorClass : inputBaseClass} pl-9`}
            />
          </div>
          {getFieldError('computerName') && (
            <p className="text-xs text-altos-danger flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" />
              {getFieldError('computerName')}
            </p>
          )}
        </div>

        {/* Password */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-altos-text">
            Password
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Lock className="h-4 w-4 text-altos-text-secondary" />
            </div>
            <input
              type={showPassword ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter a strong password"
              className={`${getFieldError('password') ? inputErrorClass : inputBaseClass} pl-9 pr-10`}
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute inset-y-0 right-0 pr-3 flex items-center text-altos-text-secondary hover:text-altos-text transition-colors duration-150"
            >
              {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </div>

          {/* Password Strength */}
          {password && (
            <div className="space-y-1.5">
              <div className="flex items-center gap-2">
                <div className="flex-1 h-1.5 bg-[#1e2127] rounded-full overflow-hidden">
                  <div
                    className={`h-full ${passwordStrength.color} transition-all duration-300`}
                    style={{ width: `${(passwordStrength.strength / 5) * 100}%` }}
                  />
                </div>
                <span className="text-xs text-altos-text-secondary min-w-[70px] text-right">{passwordStrength.label}</span>
              </div>
            </div>
          )}

          {getFieldError('password') ? (
            <p className="text-xs text-altos-danger flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" />
              {getFieldError('password')}
            </p>
          ) : (
            <p className="text-xs text-altos-text-secondary">
              At least 8 characters recommended
            </p>
          )}
        </div>

        {/* Confirm Password */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-altos-text">
            Confirm Password
          </label>
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <CheckCircle className="h-4 w-4 text-altos-text-secondary" />
            </div>
            <input
              type={showConfirmPassword ? 'text' : 'password'}
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              placeholder="Re-enter your password"
              className={`
                w-full bg-[#1a1d21] border rounded-lg px-3 py-2.5 text-sm text-altos-text pl-9 pr-10
                placeholder:text-altos-text-secondary/50
                focus:outline-none focus:ring-1 transition-colors duration-150
                ${getFieldError('confirmPassword')
                  ? 'border-altos-danger focus:border-altos-danger focus:ring-altos-danger'
                  : confirmPassword && password === confirmPassword
                    ? 'border-altos-success focus:border-altos-success focus:ring-altos-success'
                    : 'border-altos-border focus:border-altos-blue focus:ring-altos-blue'
                }
              `}
            />
            <button
              type="button"
              onClick={() => setShowConfirmPassword(!showConfirmPassword)}
              className="absolute inset-y-0 right-0 pr-3 flex items-center text-altos-text-secondary hover:text-altos-text transition-colors duration-150"
            >
              {showConfirmPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </div>
          {getFieldError('confirmPassword') && (
            <p className="text-xs text-altos-danger flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" />
              {getFieldError('confirmPassword')}
            </p>
          )}
          {confirmPassword && password === confirmPassword && !getFieldError('confirmPassword') && (
            <p className="text-xs text-altos-success flex items-center gap-1">
              <CheckCircle className="w-3 h-3" />
              Passwords match
            </p>
          )}
        </div>
      </div>

      {/* Info Box */}
      <div className="bg-[#1a1d21] border border-altos-border rounded-lg p-4 flex items-start gap-3">
        <Info className="w-5 h-5 text-altos-blue flex-shrink-0 mt-0.5" />
        <div className="text-sm text-altos-text-secondary">
          <p className="font-medium text-altos-text mb-1">Account Information</p>
          <p>
            This account will have administrator privileges. You'll use this username and password to log in to your system.
          </p>
        </div>
      </div>

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
          onClick={handleContinue}
          disabled={isLoading || !username || !computerName || !password || !confirmPassword}
          className={`
            flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium text-white
            transition-colors duration-150
            ${username && computerName && password && confirmPassword && !isLoading
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

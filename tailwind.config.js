/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        altos: {
          bg: '#1a1d21',
          card: '#25282e',
          border: '#1e2127',
          blue: '#3b82f6',
          'blue-hover': '#2563eb',
          'blue-glow': 'rgba(59, 130, 246, 0.15)',
          text: '#f2f3f5',
          'text-secondary': '#9ca3af',
          success: '#22c55e',
          warning: '#f59e0b',
          danger: '#ef4444',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'sans-serif'],
      },
      borderRadius: {
        xl: '0.75rem',
        '2xl': '1rem',
      },
    },
  },
  plugins: [],
}

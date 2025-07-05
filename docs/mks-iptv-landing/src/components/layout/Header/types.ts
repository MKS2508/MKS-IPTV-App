/**
 * Tipos e interfaces para el componente Header.
 * Define la estructura de navegación y configuración del header.
 */

export interface NavigationItem {
  label: string;
  href: string;
  isExternal?: boolean;
  icon?: string;
}

export interface HeaderProps {
  currentPath?: string;
  showLogo?: boolean;
  transparent?: boolean;
  className?: string;
}

export interface MobileMenuState {
  isOpen: boolean;
  toggle: () => void;
}

export interface ThemeToggleProps {
  currentTheme: 'light' | 'dark';
  onToggle: (theme: 'light' | 'dark') => void;
}
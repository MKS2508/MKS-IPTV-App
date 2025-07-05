/**
 * Estilos para el componente Header.
 * Organiza todas las clases de Tailwind CSS del header y navegación.
 */

export const headerStyles = {
  // Contenedor principal del header
  container: "fixed top-0 left-0 right-0 z-50 transition-all duration-300",
  
  // Variantes del header usando colores legacy
  variants: {
    transparent: "bg-transparent backdrop-blur-md",
    solid: "bg-app-surface/95 backdrop-blur-md border-b border-app-primary/30",
    scrolled: "bg-app-surface/98 backdrop-blur-md border-b border-app-primary/50 shadow-lg"
  },
  
  // Layout interno
  inner: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
  content: "flex items-center justify-between h-16 lg:h-20",
  
  // Logo y branding
  logo: {
    container: "flex items-center space-x-3",
    image: "h-8 w-8 lg:h-10 lg:w-10 object-contain",
    text: "text-xl lg:text-2xl font-bold text-app-text hover:text-app-highlight transition-colors"
  },
  
  // Navegación desktop
  nav: {
    container: "hidden md:flex items-center space-x-8",
    list: "flex items-center space-x-6 lg:space-x-8",
    item: "relative",
    link: {
      base: "text-sm lg:text-base font-medium transition-all duration-200 relative py-2",
      default: "text-app-text-muted hover:text-app-text hover:scale-105",
      active: "text-app-accent font-semibold",
      external: "text-app-text-muted hover:text-app-accent flex items-center space-x-1"
    },
    // Indicador de página activa
    activeIndicator: "absolute bottom-0 left-0 right-0 h-0.5 bg-gradient-to-r from-app-accent to-app-highlight rounded-full"
  },
  
  // Botón del menú móvil
  mobileButton: {
    container: "md:hidden flex items-center",
    button: "p-2 rounded-lg text-gray-300 hover:text-white hover:bg-slate-800/50 transition-all duration-200",
    icon: "h-6 w-6"
  },
  
  // Menú móvil
  mobileMenu: {
    overlay: "fixed inset-0 z-40 bg-black/80 backdrop-blur-sm",
    container: "fixed top-0 right-0 h-full w-64 bg-slate-900/95 backdrop-blur-xl border-l border-slate-700/50 transform transition-transform duration-300 ease-in-out",
    visible: "translate-x-0",
    hidden: "translate-x-full",
    content: "flex flex-col h-full",
    header: "flex items-center justify-between p-4 border-b border-slate-700/50",
    closeButton: "p-2 rounded-lg text-gray-300 hover:text-white hover:bg-slate-800/50 transition-all duration-200",
    nav: "flex-1 py-6",
    list: "space-y-2 px-4",
    item: "block",
    link: {
      base: "block px-4 py-3 rounded-lg text-base font-medium transition-all duration-200",
      default: "text-gray-300 hover:text-white hover:bg-slate-800/50",
      active: "text-cyan-400 bg-slate-800/30 font-semibold"
    }
  },
  
  // Animaciones
  animations: {
    fadeIn: "opacity-0 animate-fade-in",
    slideDown: "opacity-0 transform translate-y-[-10px] animate-slide-down",
    slideInRight: "opacity-0 transform translate-x-full animate-slide-in-right"
  },
  
  // Estados responsive
  responsive: {
    mobile: "block md:hidden",
    desktop: "hidden md:block",
    tablet: "hidden lg:block"
  }
} as const;

// Función helper para combinar clases de navegación
export function getNavLinkClasses(isActive: boolean, isExternal = false): string {
  const baseClasses = headerStyles.nav.link.base;
  
  if (isActive) {
    return `${baseClasses} ${headerStyles.nav.link.active}`;
  }
  
  if (isExternal) {
    return `${baseClasses} ${headerStyles.nav.link.external}`;
  }
  
  return `${baseClasses} ${headerStyles.nav.link.default}`;
}

// Función helper para clases del menú móvil
export function getMobileNavLinkClasses(isActive: boolean): string {
  const baseClasses = headerStyles.mobileMenu.link.base;
  
  if (isActive) {
    return `${baseClasses} ${headerStyles.mobileMenu.link.active}`;
  }
  
  return `${baseClasses} ${headerStyles.mobileMenu.link.default}`;
}
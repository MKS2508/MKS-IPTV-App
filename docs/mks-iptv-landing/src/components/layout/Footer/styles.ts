/**
 * Estilos para el componente Footer.
 * Organiza todas las clases de Tailwind CSS del footer.
 */

export const footerStyles = {
  // Contenedor principal
  container: "bg-slate-900/50 backdrop-blur-md border-t border-slate-700/50",
  
  // Layout interno
  inner: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
  content: "py-12 lg:py-16",
  
  // Grid principal
  grid: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8 lg:gap-12",
  
  // Sección de branding
  branding: {
    container: "md:col-span-2 lg:col-span-1",
    logo: {
      container: "flex items-center space-x-3 mb-4",
      image: "h-10 w-10 object-contain",
      text: "text-xl font-bold text-white"
    },
    description: "text-gray-400 text-sm leading-relaxed mb-6 max-w-sm",
    social: {
      container: "flex space-x-4",
      link: "text-gray-400 hover:text-cyan-400 transition-colors p-2 rounded-lg hover:bg-slate-800/50",
      icon: "h-5 w-5"
    }
  },
  
  // Secciones de enlaces
  section: {
    container: "space-y-4",
    title: "text-white font-semibold text-sm uppercase tracking-wider mb-4",
    list: "space-y-3",
    item: "block",
    link: {
      base: "text-gray-400 hover:text-white transition-colors text-sm",
      external: "text-gray-400 hover:text-cyan-400 transition-colors text-sm flex items-center space-x-1"
    }
  },
  
  // Badges de App Store
  appBadges: {
    container: "space-y-4",
    title: "text-white font-semibold text-sm uppercase tracking-wider mb-4",
    list: "space-y-3",
    badge: {
      container: "block group",
      image: "h-12 w-auto transition-transform group-hover:scale-105",
      disabled: "opacity-50 cursor-not-allowed grayscale",
      available: "hover:brightness-110"
    },
    note: "text-xs text-gray-500 mt-2"
  },
  
  // Sección inferior
  bottom: {
    container: "mt-12 pt-8 border-t border-slate-700/50",
    content: "flex flex-col md:flex-row justify-between items-center space-y-4 md:space-y-0",
    copyright: "text-gray-400 text-sm",
    links: {
      container: "flex space-x-6",
      link: "text-gray-400 hover:text-white transition-colors text-sm"
    }
  },
  
  // Animaciones
  animations: {
    fadeIn: "opacity-0 animate-fade-in",
    slideUp: "opacity-0 transform translate-y-4 animate-slide-up"
  },
  
  // Estados responsive
  responsive: {
    mobile: "block md:hidden",
    desktop: "hidden md:block",
    tablet: "block lg:hidden"
  }
} as const;

// Función helper para clases de enlaces
export function getFooterLinkClasses(isExternal = false): string {
  return isExternal 
    ? footerStyles.section.link.external 
    : footerStyles.section.link.base;
}

// Función helper para badges de app store
export function getAppBadgeClasses(available: boolean): string {
  const baseClasses = footerStyles.appBadges.badge.container;
  const stateClasses = available 
    ? footerStyles.appBadges.badge.available
    : footerStyles.appBadges.badge.disabled;
  
  return `${baseClasses} ${stateClasses}`;
}
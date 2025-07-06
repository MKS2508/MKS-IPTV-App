/**
 * Estilos para ScrollIndicator - Diseño sutil y bien integrado
 */

export const scrollIndicatorStyles = {
  container: "absolute bottom-8 left-0 right-0 mx-auto w-fit flex flex-col items-center justify-center z-50 opacity-100 visible pointer-events-none",
  
  iconWrapper: "relative mb-3 flex items-center justify-center",
  
  glow: {
    base: "absolute inset-0 rounded-full blur-lg opacity-0 w-12 h-12 top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2",
    colors: "bg-app-text-muted/10"
  },
  
  border: {
    base: "relative rounded-full p-3 backdrop-blur-sm transition-all duration-300",
    background: "bg-app-surface/20",
    border: "border border-app-text-muted/20",
    shadow: "shadow-lg shadow-app-background/50"
  },
  
  arrow: {
    base: "w-6 h-6 transition-all duration-300",
    color: "text-app-text-muted/70"
  },
  
  text: {
    base: "text-xs font-medium tracking-wider uppercase opacity-80 text-center transition-all duration-300",
    color: "text-app-text-muted/60"
  },
  
  line: {
    base: "w-px h-6 mt-3 mx-auto opacity-0 transition-all duration-500",
    gradient: "bg-gradient-to-b from-app-text-muted/30 to-transparent"
  },
  
  // Estados hover y animaciones
  states: {
    hover: "hover:scale-105",
    glow: "animate-pulse"
  }
} as const;
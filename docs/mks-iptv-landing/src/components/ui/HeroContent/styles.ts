/**
 * Estilos para HeroContent - Contenido descriptivo mejorado
 */

export const heroContentStyles = {
  container: {
    base: "flex flex-col space-y-6 max-w-2xl mx-auto",
    alignment: {
      left: "text-left items-start",
      center: "text-center items-center",
      right: "text-right items-end"
    }
  },
  
  description: {
    base: "text-lg md:text-xl leading-relaxed font-medium transition-all duration-300",
    color: "text-app-text-secondary",
    spacing: "mb-4",
    glow: "drop-shadow-[0_2px_4px_rgba(0,0,0,0.3)]"
  },
  
  tagline: {
    base: "text-base md:text-lg font-light italic leading-relaxed transition-all duration-300",
    color: "text-app-text-muted",
    spacing: "mb-6",
    glow: "drop-shadow-[0_1px_2px_rgba(0,0,0,0.2)]"
  },
  
  features: {
    container: "flex flex-wrap justify-center gap-3 mt-4",
    item: {
      base: "inline-flex items-center gap-2 px-4 py-2 rounded-full text-sm font-medium transition-all duration-300",
      background: "bg-app-surface/30 backdrop-blur-sm",
      border: "border border-app-text-muted/20",
      text: "text-app-text-muted",
      hover: "hover:bg-app-surface/50 hover:border-app-text-muted/40 hover:text-app-text-secondary"
    },
    icon: "w-4 h-4 text-app-highlight"
  },
  
  // Estados de animación
  animation: {
    initial: "opacity-0 transform scale-95 translate-y-6",
    visible: "opacity-100 transform scale-100 translate-y-0"
  },
  
  // Variantes de estilo
  variants: {
    elegant: {
      description: "font-light text-app-text-primary",
      tagline: "font-extralight text-app-text-muted/80"
    },
    bold: {
      description: "font-semibold text-app-text-primary",
      tagline: "font-medium text-app-highlight"
    },
    cyberpunk: {
      description: "font-mono text-app-accent",
      tagline: "font-mono text-app-highlight tracking-wider"
    }
  }
} as const;
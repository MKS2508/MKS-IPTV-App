/**
 * Estilos para HeroTitle - Typography hierarchy mejorada
 */

export const heroTitleStyles = {
  container: "flex flex-col items-center text-center space-y-2",
  
  subtitle: {
    base: "text-sm md:text-base font-medium tracking-widest uppercase transition-all duration-300",
    color: "text-app-highlight/90",
    spacing: "mb-2",
    glow: "drop-shadow-[0_0_8px_rgba(255,215,0,0.3)]"
  },
  
  title: {
    base: "font-bold leading-tight transition-all duration-300",
    sizes: {
      mobile: "text-4xl",
      tablet: "md:text-6xl",
      desktop: "lg:text-7xl xl:text-8xl"
    },
    color: "text-app-text-primary",
    spacing: "mb-4",
    glow: "drop-shadow-[0_0_12px_rgba(255,255,255,0.1)]"
  },
  
  // Estados de animación
  animation: {
    initial: "opacity-0 transform scale-95 translate-y-8",
    visible: "opacity-100 transform scale-100 translate-y-0"
  },
  
  // Variantes de estilo
  variants: {
    cyberpunk: {
      subtitle: "text-app-accent font-bold tracking-[0.2em]",
      title: "bg-gradient-to-r from-app-text-primary via-app-highlight to-app-text-primary bg-clip-text text-transparent"
    },
    elegant: {
      subtitle: "text-app-text-muted font-light tracking-[0.15em]",
      title: "text-app-text-primary font-light"
    },
    bold: {
      subtitle: "text-app-highlight font-extrabold tracking-[0.25em]",
      title: "text-app-text-primary font-black"
    }
  }
} as const;
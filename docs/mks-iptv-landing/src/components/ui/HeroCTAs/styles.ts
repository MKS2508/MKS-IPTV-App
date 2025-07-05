/**
 * Estilos para HeroCTAs - Botones mejorados con interacciones sutiles
 */

export const heroCTAsStyles = {
  container: {
    base: "flex items-center justify-center gap-4 mt-8",
    layouts: {
      horizontal: "flex-row flex-wrap",
      vertical: "flex-col",
      stacked: "flex-col sm:flex-row"
    }
  },
  
  button: {
    base: "relative inline-flex items-center justify-center gap-2 px-8 py-4 font-semibold text-base transition-all duration-300 rounded-lg backdrop-blur-sm border-2 overflow-hidden group",
    
    variants: {
      primary: {
        background: "bg-app-accent/90 hover:bg-app-accent",
        text: "text-app-background",
        border: "border-app-accent hover:border-app-accent",
        shadow: "shadow-lg hover:shadow-xl shadow-app-accent/25 hover:shadow-app-accent/40"
      },
      secondary: {
        background: "bg-app-highlight/20 hover:bg-app-highlight/30",
        text: "text-app-highlight hover:text-app-text-primary",
        border: "border-app-highlight/50 hover:border-app-highlight",
        shadow: "shadow-lg hover:shadow-xl shadow-app-highlight/20 hover:shadow-app-highlight/30"
      },
      outline: {
        background: "bg-transparent hover:bg-app-text-primary/10",
        text: "text-app-text-primary hover:text-app-accent",
        border: "border-app-text-primary/30 hover:border-app-accent",
        shadow: "shadow-lg hover:shadow-xl shadow-app-background/20"
      },
      ghost: {
        background: "bg-transparent hover:bg-app-surface/20",
        text: "text-app-text-muted hover:text-app-text-primary",
        border: "border-transparent hover:border-app-text-muted/30",
        shadow: "shadow-none hover:shadow-lg hover:shadow-app-background/10"
      }
    },
    
    states: {
      disabled: "opacity-50 cursor-not-allowed pointer-events-none",
      hover: "hover:scale-105 hover:-translate-y-1",
      active: "active:scale-95 active:translate-y-0"
    }
  },
  
  icon: {
    base: "w-5 h-5 transition-transform duration-300",
    animation: "group-hover:scale-110"
  },
  
  // Efectos especiales
  effects: {
    shimmer: "before:absolute before:inset-0 before:bg-gradient-to-r before:from-transparent before:via-white/10 before:to-transparent before:translate-x-[-100%] hover:before:translate-x-[100%] before:transition-transform before:duration-700",
    glow: "after:absolute after:inset-0 after:rounded-lg after:opacity-0 hover:after:opacity-100 after:transition-opacity after:duration-300",
    ripple: "relative overflow-hidden"
  },
  
  // Estados de animación
  animation: {
    initial: "opacity-0 transform scale-95 translate-y-8",
    visible: "opacity-100 transform scale-100 translate-y-0"
  }
} as const;
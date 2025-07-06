/**
 * @file Estilos para el componente Button universal.
 * @author MKS
 */

export const buttonStyles = {
  // Estilos base con transiciones CSS
  base: "relative inline-flex items-center justify-center gap-2 font-semibold text-center transition-all duration-200 rounded-lg border-2 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-transparent disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none",
  
  // Estilos base SIN transiciones CSS (para Framer Motion)
  baseNoTransition: "relative inline-flex items-center justify-center gap-2 font-semibold text-center rounded-lg border-2 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-transparent disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none",

  // Variantes de diseño
  variants: {
    primary: {
      background: "bg-app-accent hover:bg-app-accent/90",
      text: "text-app-background",
      border: "border-app-accent hover:border-app-accent/90",
      shadow: "shadow-lg hover:shadow-xl shadow-app-accent/25 hover:shadow-app-accent/40",
      focus: "focus:ring-app-accent/50"
    },
    secondary: {
      background: "bg-app-highlight/20 hover:bg-app-highlight/30 backdrop-blur-sm",
      text: "text-app-highlight hover:text-app-text-primary",
      border: "border-app-highlight/50 hover:border-app-highlight",
      shadow: "shadow-lg hover:shadow-xl shadow-app-highlight/20 hover:shadow-app-highlight/30",
      focus: "focus:ring-app-highlight/50"
    },
    outline: {
      background: "bg-transparent hover:bg-app-text-primary/10 backdrop-blur-sm",
      text: "text-app-text-primary hover:text-app-accent",
      border: "border-app-text-primary/30 hover:border-app-accent",
      shadow: "shadow-lg hover:shadow-xl shadow-app-background/20",
      focus: "focus:ring-app-accent/50"
    },
    ghost: {
      background: "bg-transparent hover:bg-app-surface/20",
      text: "text-app-text-muted hover:text-app-text-primary",
      border: "border-transparent hover:border-app-text-muted/30",
      shadow: "shadow-none hover:shadow-lg hover:shadow-app-background/10",
      focus: "focus:ring-app-text-muted/50"
    },
    danger: {
      background: "bg-red-600 hover:bg-red-700",
      text: "text-white",
      border: "border-red-600 hover:border-red-700",
      shadow: "shadow-lg hover:shadow-xl shadow-red-600/25 hover:shadow-red-600/40",
      focus: "focus:ring-red-500/50"
    },
    success: {
      background: "bg-green-600 hover:bg-green-700",
      text: "text-white",
      border: "border-green-600 hover:border-green-700",
      shadow: "shadow-lg hover:shadow-xl shadow-green-600/25 hover:shadow-green-600/40",
      focus: "focus:ring-green-500/50"
    },
    highlight: {
      background: "bg-app-highlight hover:bg-app-highlight/90",
      text: "text-app-background",
      border: "border-app-highlight hover:border-app-highlight/90",
      shadow: "shadow-lg hover:shadow-xl shadow-app-highlight/25 hover:shadow-app-highlight/40",
      focus: "focus:ring-app-highlight/50"
    }
  },

  // Tamaños
  sizes: {
    sm: {
      padding: "px-3 py-1.5",
      text: "text-sm",
      height: "h-8",
      gap: "gap-1.5",
      rounded: "rounded-md"
    },
    md: {
      padding: "px-4 py-2",
      text: "text-base",
      height: "h-10",
      gap: "gap-2",
      rounded: "rounded-lg"
    },
    lg: {
      padding: "px-6 py-3",
      text: "text-lg",
      height: "h-12",
      gap: "gap-2.5",
      rounded: "rounded-lg"
    },
    xl: {
      padding: "px-8 py-4",
      text: "text-xl",
      height: "h-14",
      gap: "gap-3",
      rounded: "rounded-xl"
    }
  },

  // Anchos
  widths: {
    auto: "w-auto",
    full: "w-full",
    fit: "w-fit"
  },

  // Iconos
  icon: {
    sizes: {
      sm: "w-4 h-4",
      md: "w-5 h-5", 
      lg: "w-6 h-6",
      xl: "w-7 h-7"
    },
    positions: {
      left: "order-first",
      right: "order-last",
      only: "mx-0"
    }
  },

  // Estados especiales
  states: {
    loading: "cursor-wait",
    disabled: "opacity-50 cursor-not-allowed pointer-events-none"
  },

  // Efectos especiales
  effects: {
    shimmer: "before:absolute before:inset-0 before:bg-gradient-to-r before:from-transparent before:via-white/10 before:to-transparent before:translate-x-[-100%] hover:before:translate-x-[100%] before:transition-transform before:duration-700 before:rounded-lg overflow-hidden",
    glow: "after:absolute after:inset-0 after:rounded-lg after:opacity-0 hover:after:opacity-100 after:transition-opacity after:duration-300",
    ripple: "relative overflow-hidden"
  },

  // Configuraciones de animación predefinidas para Framer Motion
  motionPresets: {
    // Animación suave básica
    gentle: {
      whileHover: { scale: 1.02, y: -1 },
      whileTap: { scale: 0.98 },
      transition: { type: "spring", stiffness: 400, damping: 17 }
    },
    
    // Animación más pronunciada
    bounce: {
      whileHover: { scale: 1.05, y: -2 },
      whileTap: { scale: 0.95 },
      transition: { type: "spring", stiffness: 500, damping: 15 }
    },
    
    // Solo escalado
    scale: {
      whileHover: { scale: 1.03 },
      whileTap: { scale: 0.97 },
      transition: { type: "spring", stiffness: 600, damping: 20 }
    },
    
    // Rotación sutil para iconos
    rotate: {
      whileHover: { scale: 1.02, rotate: 2 },
      whileTap: { scale: 0.98, rotate: -1 },
      transition: { type: "spring", stiffness: 400, damping: 17 }
    },
    
    // Sin animación (para accesibilidad)
    none: {
      transition: { duration: 0 }
    }
  }
} as const;
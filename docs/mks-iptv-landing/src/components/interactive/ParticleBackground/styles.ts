/**
 * Estilos para el componente ParticleBackground
 */

export const particleBackgroundStyles = {
  container: "absolute inset-0 z-0 overflow-hidden pointer-events-none",
  canvas: "absolute inset-0 w-full h-full",
  
  // Estados de carga
  loading: "opacity-0 transition-opacity duration-1000",
  loaded: "opacity-100 transition-opacity duration-1000",
  
  // Variantes de intensidad
  variants: {
    subtle: "opacity-30",
    normal: "opacity-60", 
    intense: "opacity-80",
    dramatic: "opacity-100"
  },
  
  // Responsive visibility
  responsive: {
    hideOnMobile: "hidden sm:block",
    showOnMobile: "block",
    reduceOnMobile: "opacity-50 sm:opacity-100"
  }
};

/**
 * Configuraciones predefinidas de tsParticles
 */
export const particleConfigs = {
  // Configuración por defecto - cyberpunk style
  default: {
    particles: {
      number: {
        value: 50,
        density: {
          enable: true,
          value_area: 800
        }
      },
      color: {
        value: ["#C62790", "#FFD700", "#463564"]
      },
      shape: {
        type: "circle"
      },
      opacity: {
        value: { min: 0.1, max: 0.8 },
        animation: {
          enable: true,
          speed: 1,
          minimumValue: 0.1
        }
      },
      size: {
        value: { min: 1, max: 4 },
        animation: {
          enable: true,
          speed: 2,
          minimumValue: 0.5
        }
      },
      move: {
        enable: true,
        speed: 1,
        direction: "none",
        random: true,
        straight: false,
        outModes: "out"
      }
    },
    interactivity: {
      detectsOn: "canvas",
      events: {
        onHover: {
          enable: true,
          mode: "attract"
        },
        resize: true
      },
      modes: {
        attract: {
          distance: 200,
          duration: 0.4,
          speed: 1
        }
      }
    },
    detectRetina: true
  },

  // Configuración minimalista
  minimal: {
    particles: {
      number: {
        value: 20,
        density: {
          enable: true,
          value_area: 1000
        }
      },
      color: {
        value: "#463564"
      },
      opacity: {
        value: 0.3
      },
      size: {
        value: 2
      },
      move: {
        enable: true,
        speed: 0.5,
        direction: "none",
        random: true
      }
    },
    interactivity: {
      events: {
        resize: true
      }
    }
  },

  // Configuración para móviles
  mobile: {
    particles: {
      number: {
        value: 15,
        density: {
          enable: true,
          value_area: 600
        }
      },
      color: {
        value: "#C62790"
      },
      opacity: {
        value: 0.4
      },
      size: {
        value: 3
      },
      move: {
        enable: true,
        speed: 0.8,
        direction: "none"
      }
    },
    interactivity: {
      events: {
        resize: true
      }
    }
  }
};
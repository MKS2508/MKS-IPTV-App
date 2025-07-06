/**
 * @file Animaciones GSAP para Button component
 * @description Presets y utilidades para animaciones GSAP del botón
 * @author MKS
 */

import { gsap } from 'gsap';
import type { GSAPAnimationConfig, AnimationPreset } from './types';

/**
 * Presets de animación GSAP equivalentes a Framer Motion
 */
export const gsapAnimationPresets: Record<AnimationPreset, GSAPAnimationConfig> = {
  // Animación suave básica
  gentle: {
    hover: {
      scale: 1.02,
      y: -1,
      duration: 0.3,
      ease: "power2.out"
    },
    tap: {
      scale: 0.98,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Animación más pronunciada con bounce
  bounce: {
    hover: {
      scale: 1.05,
      y: -2,
      duration: 0.4,
      ease: "back.out(1.7)"
    },
    tap: {
      scale: 0.95,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Animación elástica sofisticada
  elastic: {
    hover: {
      scale: 1.03,
      rotation: 2,
      duration: 0.5,
      ease: "elastic.out(1, 0.5)"
    },
    tap: {
      scale: 0.97,
      rotation: -1,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Solo escalado simple
  scale: {
    hover: {
      scale: 1.03,
      duration: 0.25,
      ease: "power2.out"
    },
    tap: {
      scale: 0.97,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Rotación sutil para iconos
  rotate: {
    hover: {
      scale: 1.02,
      rotation: 5,
      duration: 0.3,
      ease: "power2.out"
    },
    tap: {
      scale: 0.98,
      rotation: -2,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // ===== ANIMACIONES AVANZADAS GSAP =====
  
  // Magnetismo realista con physics avanzadas
  magnetic: {
    hover: {
      scale: 1.03,
      y: -3,
      boxShadow: "0 15px 35px rgba(0,0,0,0.25)",
      duration: 0.4,
      ease: "power2.out"
    },
    tap: {
      scale: 0.98,
      y: 0,
      boxShadow: "0 5px 15px rgba(0,0,0,0.1)",
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Oscillación sofisticada con rotation compleja
  oscillate: {
    hover: {
      scale: 1.05,
      rotation: "2_ccw",
      transformOrigin: "center center",
      duration: 0.6,
      ease: "elastic.out(1, 0.6)",
      repeat: 2,
      yoyo: true
    },
    tap: {
      scale: 0.95,
      rotation: 0,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Morphing avanzado con skew y borders
  morph: {
    hover: {
      scale: 1.04,
      borderRadius: "50%",
      skewX: 2,
      rotation: 8,
      transformOrigin: "center center",
      duration: 0.5,
      ease: "back.out(1.4)"
    },
    tap: {
      scale: 0.96,
      borderRadius: "20%",
      skewX: -1,
      rotation: -3,
      duration: 0.15,
      ease: "power2.out"
    }
  },
  
  // Respiración orgánica con timeline
  breathe: {
    hover: {
      scale: 1.06,
      opacity: 1,
      duration: 0.3,
      ease: "power2.out"
    },
    tap: {
      scale: 0.95,
      duration: 0.1,
      ease: "power2.out"
    },
    // Animación continua se maneja en setupBreathingAnimation()
    animate: {
      scale: [1, 1.02, 1],
      opacity: [1, 0.9, 1],
      duration: 2.5,
      ease: "sine.inOut",
      repeat: -1,
      yoyo: true
    }
  },
  
  // Glow dinámico con filtros
  glow: {
    hover: {
      scale: 1.03,
      filter: "drop-shadow(0 0 20px rgba(59, 130, 246, 0.4))",
      duration: 0.4,
      ease: "power2.out"
    },
    tap: {
      scale: 0.98,
      filter: "drop-shadow(0 0 10px rgba(59, 130, 246, 0.2))",
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Floating continuo con movimiento complejo
  floating: {
    hover: {
      y: -6,
      scale: 1.03,
      duration: 0.3,
      ease: "power2.out"
    },
    tap: {
      y: 0,
      scale: 0.97,
      duration: 0.1,
      ease: "power2.out"
    },
    // Animación continua se maneja en setupFloatingAnimation()
    animate: {
      y: [-3, 3, -3],
      rotation: [-1, 1, -1],
      duration: 4,
      ease: "sine.inOut",
      repeat: -1,
      yoyo: true
    }
  },
  
  // Liquid deformation avanzada
  liquid: {
    hover: {
      scale: [1, 1.1, 0.95, 1.05],
      skewX: [0, 3, -2, 0],
      transformOrigin: "center center",
      duration: 0.8,
      ease: "power2.inOut"
    },
    tap: {
      scale: 0.9,
      skewX: 4,
      duration: 0.1,
      ease: "power2.out"
    }
  },
  
  // Sin animación
  none: {
    hover: { duration: 0 },
    tap: { duration: 0 }
  }
};

/**
 * Wrapper para animaciones GSAP de botones
 */
export class GSAPButtonAnimator {
  private element: HTMLElement | null = null;
  private hoverTween: gsap.core.Tween | null = null;
  private tapTween: gsap.core.Tween | null = null;
  private continuousTween: gsap.core.Tween | null = null;
  private config: GSAPAnimationConfig;
  private isDestroyed = false;
  private eventListeners: Array<{ element: HTMLElement; event: string; handler: EventListener }> = [];

  constructor(element: HTMLElement, config: GSAPAnimationConfig) {
    this.element = element;
    this.config = config;
    
    // Debugging
    if (process.env.NODE_ENV === 'development') {
      console.log('🎨 GSAPButtonAnimator Created:', {
        element: element.tagName,
        config: config,
        hasHover: !!config.hover,
        hasTap: !!config.tap
      });
    }
    
    this.init();
  }

  /**
   * Inicializa las animaciones
   */
  private init() {
    if (!this.element) return;

    // Configuración inicial
    if (this.config.initial) {
      gsap.set(this.element, this.config.initial);
    }

    // Animación de entrada
    if (this.config.animate) {
      gsap.fromTo(this.element, 
        this.config.initial || {},
        {
          ...this.config.animate,
          ease: this.config.animate.ease || "power2.out"
        }
      );
    }

    // Eventos de hover
    if (this.config.hover) {
      this.setupHoverAnimation();
    }

    // Eventos de tap/click
    if (this.config.tap) {
      this.setupTapAnimation();
    }

    // ScrollTrigger integration
    if (this.config.scrollTrigger) {
      this.setupScrollTrigger();
    }

    // Continuous animations
    if (this.config.animate) {
      this.setupContinuousAnimation();
    }
  }

  /**
   * Configura animación de hover
   */
  private setupHoverAnimation() {
    if (!this.element || !this.config.hover) return;

    // Debugging
    if (process.env.NODE_ENV === 'development') {
      console.log('🐭 Setting up hover animation:', {
        element: this.element.tagName,
        hoverConfig: this.config.hover
      });
    }

    // Approach directo sin paused/reverse para mejor compatibilidad
    const mouseEnterHandler = () => {
      if (this.isDestroyed) return;
      if (process.env.NODE_ENV === 'development') {
        console.log('💁 Mouse enter - animating to hover state');
      }
      
      // Matar tween anterior si existe
      if (this.hoverTween) {
        this.hoverTween.kill();
      }
      
      // Crear nueva animación hacia el estado hover
      this.hoverTween = gsap.to(this.element, {
        ...this.config.hover,
        duration: this.config.hover?.duration || 0.3,
        ease: this.config.hover?.ease || "power2.out"
      });
    };
    
    const mouseLeaveHandler = () => {
      if (this.isDestroyed) return;
      if (process.env.NODE_ENV === 'development') {
        console.log('💁 Mouse leave - animating back to default');
      }
      
      // Matar tween anterior si existe
      if (this.hoverTween) {
        this.hoverTween.kill();
      }
      
      // Animar de vuelta al estado default
      this.hoverTween = gsap.to(this.element, {
        scale: 1,
        rotation: 0,
        y: 0,
        x: 0,
        duration: 0.2,
        ease: "power2.out"
      });
    };
    
    this.element.addEventListener('mouseenter', mouseEnterHandler);
    this.element.addEventListener('mouseleave', mouseLeaveHandler);
    
    // Guardar referencias para cleanup
    this.eventListeners.push(
      { element: this.element, event: 'mouseenter', handler: mouseEnterHandler },
      { element: this.element, event: 'mouseleave', handler: mouseLeaveHandler }
    );
  }

  /**
   * Configura animación de tap/click
   */
  private setupTapAnimation() {
    if (!this.element || !this.config.tap) return;

    const mouseDownHandler = () => {
      if (this.isDestroyed) return;
      if (process.env.NODE_ENV === 'development') {
        console.log('💆 Mouse down - tap animation');
      }
      
      this.tapTween?.kill();
      this.tapTween = gsap.to(this.element, {
        ...this.config.tap,
        duration: this.config.tap?.duration || 0.1,
        ease: this.config.tap?.ease || "power2.out"
      });
    };

    const mouseUpHandler = () => {
      if (this.isDestroyed) return;
      if (process.env.NODE_ENV === 'development') {
        console.log('💆 Mouse up - return from tap');
      }
      
      // Volver al estado default rápidamente
      this.tapTween?.kill();
      this.tapTween = gsap.to(this.element, {
        scale: 1,
        rotation: 0,
        y: 0,
        x: 0,
        duration: 0.15,
        ease: "power2.out"
      });
    };

    const tapMouseLeaveHandler = () => {
      if (this.isDestroyed) return;
      // Si sale el mouse, volver al estado default
      this.tapTween?.kill();
      this.tapTween = gsap.to(this.element, {
        scale: 1,
        rotation: 0,
        y: 0,
        x: 0,
        duration: 0.2,
        ease: "power2.out"
      });
    };
    
    this.element.addEventListener('mousedown', mouseDownHandler);
    this.element.addEventListener('mouseup', mouseUpHandler);
    this.element.addEventListener('mouseleave', tapMouseLeaveHandler);
    
    // Guardar referencias para cleanup
    this.eventListeners.push(
      { element: this.element, event: 'mousedown', handler: mouseDownHandler },
      { element: this.element, event: 'mouseup', handler: mouseUpHandler },
      { element: this.element, event: 'mouseleave', handler: tapMouseLeaveHandler }
    );
  }

  /**
   * Configura animaciones continuas (breathe, floating, etc.)
   */
  private setupContinuousAnimation() {
    if (!this.element || !this.config.animate) return;

    // Debugging
    if (process.env.NODE_ENV === 'development') {
      console.log('🔄 Setting up continuous animation:', {
        element: this.element.tagName,
        animateConfig: this.config.animate
      });
    }

    // Crear animación continua
    this.continuousTween = gsap.to(this.element, {
      ...this.config.animate,
      ease: this.config.animate.ease || "sine.inOut",
      repeat: this.config.animate.repeat ?? -1,
      yoyo: this.config.animate.yoyo ?? true
    });
  }

  /**
   * Configura ScrollTrigger para integración con scroll
   */
  private setupScrollTrigger() {
    if (!this.element || !this.config.scrollTrigger) return;

    // Lazy load ScrollTrigger
    import('gsap/ScrollTrigger').then(({ ScrollTrigger }) => {
      gsap.registerPlugin(ScrollTrigger);

      ScrollTrigger.create({
        trigger: this.config.scrollTrigger?.trigger || this.element,
        start: this.config.scrollTrigger?.start || "top 80%",
        end: this.config.scrollTrigger?.end || "bottom 20%",
        scrub: this.config.scrollTrigger?.scrub || false,
        animation: gsap.fromTo(this.element, 
          { opacity: 0, y: 30 },
          { opacity: 1, y: 0, duration: 0.6, ease: "power2.out" }
        )
      });
    });
  }

  /**
   * Actualiza la configuración de animación
   */
  updateConfig(newConfig: GSAPAnimationConfig) {
    this.destroy();
    this.config = newConfig;
    this.isDestroyed = false;
    this.init();
  }

  /**
   * Conecta con timeline global para Hero CTAs
   */
  connectToTimeline(timelineName: string) {
    if (this.config.timeline !== timelineName) return;

    // Buscar timeline global (ej: Hero timeline)
    const globalTimeline = (window as any).gsapTimelines?.[timelineName];
    
    if (globalTimeline && this.element) {
      globalTimeline.fromTo(this.element,
        { opacity: 0, scale: 0.8, y: 20 },
        { 
          opacity: 1, 
          scale: 1, 
          y: 0, 
          duration: 0.6,
          ease: "back.out(1.7)"
        },
        "-=0.3" // Overlap con animación anterior
      );
    }
  }

  /**
   * Limpia todas las animaciones y eventos
   */
  destroy() {
    this.isDestroyed = true;
    
    if (this.hoverTween) {
      this.hoverTween.kill();
      this.hoverTween = null;
    }
    
    if (this.tapTween) {
      this.tapTween.kill();
      this.tapTween = null;
    }

    if (this.continuousTween) {
      this.continuousTween.kill();
      this.continuousTween = null;
    }

    // Limpiar event listeners guardados
    this.eventListeners.forEach(({ element, event, handler }) => {
      element.removeEventListener(event, handler);
    });
    this.eventListeners = [];
  }
}

/**
 * Factory para crear animaciones GSAP predefinidas
 */
export class GSAPAnimationFactory {
  /**
   * Crea animación desde preset
   */
  static fromPreset(preset: AnimationPreset): GSAPAnimationConfig {
    return gsapAnimationPresets[preset];
  }

  /**
   * Crea animación optimizada para contexto
   */
  static forContext(context: 'cta' | 'hero' | 'scroll'): GSAPAnimationConfig {
    const configs = {
      cta: {
        ...gsapAnimationPresets.bounce,
        hover: {
          ...gsapAnimationPresets.bounce.hover,
          boxShadow: "0 20px 60px rgba(59, 130, 246, 0.3)"
        }
      },
      hero: {
        ...gsapAnimationPresets.elastic,
        timeline: 'hero',
        initial: { opacity: 0, scale: 0.8, y: 20 },
        animate: { opacity: 1, scale: 1, y: 0, duration: 0.8, ease: "back.out(1.7)" }
      },
      scroll: {
        ...gsapAnimationPresets.gentle,
        scrollTrigger: {
          start: "top 90%",
          end: "bottom 10%",
          scrub: 1
        },
        initial: { opacity: 0, y: 30 },
        animate: { opacity: 1, y: 0, duration: 0.6 }
      }
    };

    return configs[context];
  }

  /**
   * Combina múltiples configuraciones
   */
  static combine(...configs: Partial<GSAPAnimationConfig>[]): GSAPAnimationConfig {
    return configs.reduce((acc, config) => ({
      ...acc,
      ...config,
      hover: { ...acc.hover, ...config.hover },
      tap: { ...acc.tap, ...config.tap },
      scrollTrigger: { ...acc.scrollTrigger, ...config.scrollTrigger }
    }), {} as GSAPAnimationConfig);
  }
}

/**
 * Utilidades para performance de animaciones GSAP
 */
export class GSAPPerformanceUtils {
  private static animators = new Set<GSAPButtonAnimator>();
  
  /**
   * Registra un animator para cleanup automático
   */
  static register(animator: GSAPButtonAnimator) {
    this.animators.add(animator);
  }

  /**
   * Desregistra un animator
   */
  static unregister(animator: GSAPButtonAnimator) {
    this.animators.delete(animator);
  }

  /**
   * Limpia todos los animators (para limpieza global)
   */
  static cleanup() {
    this.animators.forEach(animator => animator.destroy());
    this.animators.clear();
  }

  /**
   * Optimiza performance basado en device capabilities
   */
  static getOptimizedConfig(baseConfig: GSAPAnimationConfig): GSAPAnimationConfig {
    // Detectar device de baja potencia
    const isLowPowerDevice = this.isLowPowerDevice();
    
    if (isLowPowerDevice) {
      return {
        ...baseConfig,
        hover: baseConfig.hover ? { ...baseConfig.hover, duration: 0.1 } : undefined,
        tap: baseConfig.tap ? { ...baseConfig.tap, duration: 0.05 } : undefined
      };
    }

    return baseConfig;
  }

  /**
   * Detecta dispositivos de baja potencia
   */
  private static isLowPowerDevice(): boolean {
    // Aproximación básica para detectar dispositivos low-end
    const hardwareConcurrency = navigator.hardwareConcurrency || 4;
    const memoryGB = (navigator as any).deviceMemory || 4;
    
    return hardwareConcurrency <= 2 || memoryGB <= 2;
  }
}
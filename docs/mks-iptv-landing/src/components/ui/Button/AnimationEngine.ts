/**
 * @file Motor de animación inteligente para Button component
 * @description Sistema que detecta automáticamente el motor óptimo de animación
 * @author MKS
 */

import type { 
  ButtonMotionConfig, 
  AnimationEngine, 
  AnimationPreset,
  SerializableMotionConfig 
} from './types';

/**
 * Detecta automáticamente el motor de animación óptimo
 */
export class AnimationEngineSelector {
  /**
   * Determina qué motor usar basado en la configuración
   */
  static detectEngine(config: ButtonMotionConfig): AnimationEngine {
    // Si se especifica explícitamente, usar ese
    if (config.engine && config.engine !== 'auto') {
      return config.engine;
    }

    // Si hay configuración GSAP específica, usar GSAP
    if (config.gsap) {
      return 'gsap';
    }

    // Si hay configuración Framer Motion específica, usar Framer
    if (config.framer && this.hasFramerConfig(config.framer)) {
      return 'framer';
    }

    // Si solo hay preset, usar Framer Motion (mejor para presets)
    if (config.preset && config.preset !== 'none') {
      return 'framer';
    }

    // Default: CSS para mejor performance
    return 'css';
  }

  /**
   * Verifica si hay configuración específica de Framer Motion
   */
  private static hasFramerConfig(framerConfig: any): boolean {
    return !!(
      framerConfig.variants ||
      framerConfig.whileHover ||
      framerConfig.whileTap ||
      framerConfig.initial ||
      framerConfig.animate ||
      framerConfig.layout
    );
  }

  /**
   * Verifica si el usuario prefiere motion reducido
   */
  static respectsReducedMotion(): boolean {
    if (typeof window === 'undefined') return false;
    
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  /**
   * Aplica configuración de motion reducido
   */
  static applyReducedMotion(config: ButtonMotionConfig): ButtonMotionConfig {
    if (!this.respectsReducedMotion() && !config.respectReducedMotion) {
      return config;
    }

    // Forzar uso de CSS y preset 'none'
    return {
      ...config,
      engine: 'css',
      preset: 'none',
      framer: undefined,
      gsap: undefined,
    };
  }

  /**
   * Convierte configuración serializable de Astro a ButtonMotionConfig
   */
  static fromSerializable(serializable: SerializableMotionConfig): ButtonMotionConfig {
    const config: ButtonMotionConfig = {
      engine: serializable.engine,
      preset: serializable.preset,
      respectReducedMotion: serializable.respectReducedMotion,
      duration: serializable.duration,
    };

    // Convertir configuración Framer Motion
    if (serializable.framer) {
      config.framer = {
        whileHover: serializable.framer.whileHover,
        whileTap: serializable.framer.whileTap,
        initial: serializable.framer.initial,
        animate: serializable.framer.animate,
        transition: serializable.framer.transition,
        layout: serializable.framer.layout,
        layoutId: serializable.framer.layoutId,
      };
    }

    // Convertir configuración GSAP
    if (serializable.gsap) {
      config.gsap = {
        hover: serializable.gsap.hover,
        tap: serializable.gsap.tap,
        initial: serializable.gsap.initial,
        animate: serializable.gsap.animate,
        timeline: serializable.gsap.timeline,
        scrollTrigger: serializable.gsap.scrollTrigger,
      };
    }

    return config;
  }

  /**
   * Obtiene configuración optimizada para el contexto
   */
  static getOptimalConfig(
    context: 'button' | 'cta' | 'form' | 'hero',
    preset?: AnimationPreset
  ): ButtonMotionConfig {
    const baseConfigs = {
      button: { engine: 'framer' as AnimationEngine, preset: 'gentle' as AnimationPreset },
      cta: { engine: 'gsap' as AnimationEngine, preset: 'bounce' as AnimationPreset },
      form: { engine: 'css' as AnimationEngine, preset: 'none' as AnimationPreset },
      hero: { engine: 'gsap' as AnimationEngine, preset: 'elastic' as AnimationPreset },
    };

    const config = baseConfigs[context];
    
    return {
      ...config,
      preset: preset || config.preset,
      respectReducedMotion: true,
    };
  }
}

/**
 * Utilidades para debugging de animaciones
 */
export class AnimationDebugger {
  private static enabled = process.env.NODE_ENV === 'development';

  static log(message: string, config?: any) {
    if (!this.enabled) return;
    
    console.group(`🎭 Animation Engine: ${message}`);
    if (config) {
      console.log('Config:', config);
    }
    console.groupEnd();
  }

  static warn(message: string, config?: any) {
    if (!this.enabled) return;
    
    console.warn(`⚠️ Animation Warning: ${message}`, config);
  }

  static error(message: string, error?: any) {
    console.error(`❌ Animation Error: ${message}`, error);
  }
}
/**
 * Types for ParticleBackground component
 */

export interface ParticleBackgroundProps {
  /** ID único para el contenedor de partículas */
  id?: string;
  /** Número de partículas a generar */
  particleCount?: number;
  /** Color de las partículas (hex o variable CSS) */
  particleColor?: string;
  /** Velocidad de movimiento de las partículas */
  speed?: number;
  /** Tamaño de las partículas */
  size?: {
    min: number;
    max: number;
  };
  /** Opacidad de las partículas */
  opacity?: {
    min: number;
    max: number;
  };
  /** Habilitar conexiones entre partículas */
  enableConnections?: boolean;
  /** Distancia máxima para conexiones */
  connectionDistance?: number;
  /** Respuesta al hover del mouse */
  interactivity?: {
    enable: boolean;
    distance: number;
    attract: boolean;
  };
  /** Configuración responsive */
  responsive?: {
    mobile: {
      particleCount: number;
      speed: number;
    };
    tablet: {
      particleCount: number;
      speed: number;
    };
  };
  /** Clases CSS adicionales */
  className?: string;
}

export interface ParticleEngine {
  /** Instancia de tsParticles */
  container?: any;
  /** Estado de inicialización */
  initialized: boolean;
  /** Función de cleanup */
  destroy: () => void;
}
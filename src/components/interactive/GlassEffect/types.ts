/**
 * Tipos para el componente GlassEffect
 */

/**
 * Presets disponibles para el efecto glass
 */
export type GlassPreset = 'dock' | 'pill' | 'bubble' | 'free';

/**
 * Configuración de preset para el efecto glass
 */
export interface PresetConfig {
  /** Ancho del componente */
  width: number;
  /** Alto del componente */
  height: number;
  /** Radio del borde */
  borderRadius: number;
  /** Intensidad del blur */
  blurAmount: number;
  /** Escala del displacement */
  displacementScale: number;
  /** Color del borde */
  borderColor: string;
  /** Grosor del borde */
  borderWidth: number;
  /** Opacidad del fondo */
  backgroundOpacity: number;
  /** Si es arrastrable */
  draggable: boolean;
  /** Posición inicial X */
  initialX?: number;
  /** Posición inicial Y */
  initialY?: number;
}

/**
 * Props del componente GlassEffect
 */
export interface GlassEffectProps {
  /** Preset a utilizar */
  preset?: GlassPreset;
  /** Contenido a mostrar dentro del glass */
  children?: React.ReactNode;
  /** Clase CSS adicional */
  className?: string;
  /** ID único para el componente */
  id?: string;
  /** Callback cuando se arrastra */
  onDrag?: (x: number, y: number) => void;
  /** Configuración personalizada (override del preset) */
  customConfig?: Partial<PresetConfig>;
}

/**
 * Estado interno del componente
 */
export interface GlassEffectState {
  /** Posición actual X */
  x: number;
  /** Posición actual Y */
  y: number;
  /** Si está siendo arrastrado */
  isDragging: boolean;
  /** ID único para los filtros SVG */
  filterId: string;
}

/**
 * Props para el filtro SVG
 */
export interface SVGFilterProps {
  /** ID único del filtro */
  id: string;
  /** Escala del displacement */
  displacementScale: number;
  /** Cantidad de blur */
  blurAmount: number;
}
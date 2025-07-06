/**
 * @file Tipos para el componente GlassEffect.
 * @author MKS
 */

import type { ReactNode } from 'react';

export type GlassPreset = 'dock' | 'pill' | 'bubble' | 'free';

export type BlendMode = 
  | 'normal' | 'multiply' | 'screen' | 'overlay' 
  | 'darken' | 'lighten' | 'color-dodge' | 'color-burn'
  | 'hard-light' | 'soft-light' | 'difference' | 'exclusion'
  | 'hue' | 'saturation' | 'color' | 'luminosity';

export type ChannelSelector = 'R' | 'G' | 'B';

export interface GlassConfig {
  // Dimensiones
  width: number;
  height: number;
  radius: number;
  
  // Efecto visual
  frost: number;
  displace: number;
  scale: number;
  border: number;
  alpha: number;
  lightness: number;
  blur: number;
  
  // Canales
  x: ChannelSelector;
  y: ChannelSelector;
  blend: BlendMode;
  
  // Chromatic aberration
  r: number;
  g: number;
  b: number;
}

export interface GlassEffectProps {
  /** Preset predefinido */
  preset?: GlassPreset;
  /** Configuración personalizada (sobrescribe preset) */
  config?: Partial<GlassConfig>;
  /** Contenido interno del efecto glass */
  children?: ReactNode;
  /** Habilitar dragging */
  draggable?: boolean;
  /** Posición inicial */
  initialPosition?: { x: number; y: number };
  /** Clases CSS adicionales */
  className?: string;
  /** Callback cuando se mueve */
  onMove?: (x: number, y: number) => void;
}
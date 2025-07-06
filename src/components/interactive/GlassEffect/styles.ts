/**
 * Estilos y configuraciones para el componente GlassEffect
 */

import type { GlassPreset, PresetConfig } from './types';

/**
 * Configuraciones de presets predefinidos
 */
export const presetConfigs: Record<GlassPreset, PresetConfig> = {
  dock: {
    width: 320,
    height: 80,
    borderRadius: 24,
    blurAmount: 8,
    displacementScale: 15,
    borderColor: 'rgba(255, 255, 255, 0.2)',
    borderWidth: 1,
    backgroundOpacity: 0.15,
    draggable: true,
    initialX: 50,
    initialY: 200,
  },
  pill: {
    width: 200,
    height: 60,
    borderRadius: 30,
    blurAmount: 12,
    displacementScale: 10,
    borderColor: 'rgba(255, 255, 255, 0.3)',
    borderWidth: 2,
    backgroundOpacity: 0.2,
    draggable: true,
    initialX: 100,
    initialY: 150,
  },
  bubble: {
    width: 150,
    height: 150,
    borderRadius: 75,
    blurAmount: 20,
    displacementScale: 25,
    borderColor: 'rgba(255, 255, 255, 0.4)',
    borderWidth: 3,
    backgroundOpacity: 0.1,
    draggable: true,
    initialX: 150,
    initialY: 100,
  },
  free: {
    width: 280,
    height: 120,
    borderRadius: 16,
    blurAmount: 15,
    displacementScale: 20,
    borderColor: 'rgba(255, 255, 255, 0.25)',
    borderWidth: 1.5,
    backgroundOpacity: 0.18,
    draggable: true,
    initialX: 200,
    initialY: 250,
  },
};

/**
 * Clases CSS base para el componente
 */
export const baseStyles = {
  container: `
    relative 
    cursor-grab 
    select-none 
    backdrop-blur-sm 
    transition-all 
    duration-300 
    ease-out
    hover:backdrop-blur-md
  `,
  glassElement: `
    absolute 
    inset-0 
    rounded-lg 
    border 
    backdrop-blur-lg 
    backdrop-saturate-150
    shadow-2xl
    shadow-white/10
  `,
  content: `
    relative 
    z-10 
    p-4 
    text-white 
    font-medium 
    text-center 
    flex 
    items-center 
    justify-center 
    w-full 
    h-full
  `,
  dragging: `
    cursor-grabbing 
    scale-105 
    shadow-3xl 
    shadow-white/20
  `,
  svg: `
    absolute 
    inset-0 
    w-full 
    h-full 
    pointer-events-none
  `,
};

/**
 * Función para generar ruido para el displacement map
 */
export const generateNoiseData = (width: number, height: number): string => {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  
  if (!ctx) return '';
  
  const imageData = ctx.createImageData(width, height);
  const data = imageData.data;
  
  for (let i = 0; i < data.length; i += 4) {
    const noise = Math.random() * 255;
    data[i] = noise;     // Red
    data[i + 1] = noise; // Green
    data[i + 2] = noise; // Blue
    data[i + 3] = 255;   // Alpha
  }
  
  ctx.putImageData(imageData, 0, 0);
  return canvas.toDataURL();
};

/**
 * Configuración de animaciones GSAP
 */
export const animationConfig = {
  drag: {
    type: 'x,y',
    bounds: 'window',
    inertia: true,
    edgeResistance: 0.8,
    throwProps: {
      resistance: 300,
    },
  },
  hover: {
    scale: 1.02,
    duration: 0.3,
    ease: 'power2.out',
  },
  initial: {
    opacity: 0,
    scale: 0.9,
    duration: 0.6,
    ease: 'power3.out',
  },
};
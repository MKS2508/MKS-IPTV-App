/**
 * @file Estilos para el componente GlassEffect.
 * @author MKS
 */

export const glassEffectStyles = {
  container: `
    position fixed z-50 opacity-0 transition-opacity duration-300 ease-out
    backdrop-blur-md
  `,
  
  effect: `
    w-full h-full overflow-hidden
    backdrop-filter: url(#glassFilter) brightness(1.1) saturate(1.5);
    background: light-dark(
      hsl(0 0% 100% / var(--frost, 0)),
      hsl(0 0% 0% / var(--frost, 0))
    );
    box-shadow: 
      0 0 2px 1px hsl(0 0% 15% / 0.15) inset,
      0 0 10px 4px hsl(0 0% 15% / 0.1) inset,
      0px 4px 16px rgba(17, 17, 26, 0.05),
      0px 8px 24px rgba(17, 17, 26, 0.05),
      0px 16px 56px rgba(17, 17, 26, 0.05),
      0px 4px 16px rgba(17, 17, 26, 0.05) inset,
      0px 8px 24px rgba(17, 17, 26, 0.05) inset,
      0px 16px 56px rgba(17, 17, 26, 0.05) inset;
  `,
  
  content: `
    w-full h-full flex items-center justify-center
    pointer-events-none
  `,
  
  draggable: `
    cursor-grab active:cursor-grabbing
  `,
  
  filter: `
    w-full h-full pointer-events-none absolute inset-0
  `,
} as const;

export const glassPresets = {
  dock: {
    width: 336,
    height: 96,
    radius: 16,
    frost: 0.05,
    displace: 0.2,
    scale: -180,
    border: 0.07,
    alpha: 0.93,
    lightness: 50,
    blur: 11,
    x: 'R' as const,
    y: 'B' as const,
    blend: 'difference' as const,
    r: 0,
    g: 10,
    b: 20,
  },
  
  pill: {
    width: 200,
    height: 80,
    radius: 40,
    frost: 0,
    displace: 0,
    scale: -180,
    border: 0.07,
    alpha: 0.93,
    lightness: 50,
    blur: 11,
    x: 'R' as const,
    y: 'B' as const,
    blend: 'difference' as const,
    r: 0,
    g: 10,
    b: 20,
  },
  
  bubble: {
    width: 140,
    height: 140,
    radius: 70,
    frost: 0,
    displace: 0,
    scale: -180,
    border: 0.07,
    alpha: 0.93,
    lightness: 50,
    blur: 11,
    x: 'R' as const,
    y: 'B' as const,
    blend: 'difference' as const,
    r: 0,
    g: 10,
    b: 20,
  },
  
  free: {
    width: 140,
    height: 280,
    radius: 80,
    frost: 0,
    displace: 0,
    scale: -300,
    border: 0.15,
    alpha: 0.74,
    lightness: 60,
    blur: 10,
    x: 'R' as const,
    y: 'B' as const,
    blend: 'difference' as const,
    r: 0,
    g: 10,
    b: 20,
  },
} as const;
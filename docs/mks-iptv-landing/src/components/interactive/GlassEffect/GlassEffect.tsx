/**
 * @file Componente React para efectos de glass con desplazamiento.
 * @author MKS
 */

import { useEffect, useRef, useState } from 'react';
import { gsap } from 'gsap';
import { Draggable } from 'gsap/Draggable';
import type { GlassEffectProps, GlassConfig } from './types';
import { glassPresets } from './styles';

gsap.registerPlugin(Draggable);

export const GlassEffect: React.FC<GlassEffectProps> = ({
  preset = 'dock',
  config = {},
  children,
  draggable = true,
  initialPosition = { x: 50, y: 50 },
  className = '',
  onMove,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const filterRef = useRef<SVGSVGElement>(null);
  const [isVisible, setIsVisible] = useState(false);
  const [currentConfig, setCurrentConfig] = useState<GlassConfig>({
    ...glassPresets[preset],
    ...config,
  });

  // Generar imagen de desplazamiento SVG
  const generateDisplacementImage = () => {
    const { width, height, radius, border, alpha, lightness, blur, blend } = currentConfig;
    const borderSize = Math.min(width, height) * (border * 0.5);

    const svg = `
      <svg viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <linearGradient id="red" x1="100%" y1="0%" x2="0%" y2="0%">
            <stop offset="0%" stop-color="#0000"/>
            <stop offset="100%" stop-color="red"/>
          </linearGradient>
          <linearGradient id="blue" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stop-color="#0000"/>
            <stop offset="100%" stop-color="blue"/>
          </linearGradient>
        </defs>
        <rect x="0" y="0" width="${width}" height="${height}" fill="black"></rect>
        <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" fill="url(#red)" />
        <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" fill="url(#blue)" style="mix-blend-mode: ${blend}" />
        <rect x="${borderSize}" y="${borderSize}" width="${width - borderSize * 2}" height="${height - borderSize * 2}" rx="${radius}" fill="hsl(0 0% ${lightness}% / ${alpha})" style="filter:blur(${blur}px)" />
      </svg>
    `;

    return `data:image/svg+xml;base64,${btoa(svg)}`;
  };

  // Generar SVG filter dinámicamente
  const generateSVGFilter = () => {
    const { scale, x, y, r, g, b } = currentConfig;
    const displacementImage = generateDisplacementImage();

    return (
      <svg
        ref={filterRef}
        className="w-full h-full pointer-events-none absolute inset-0"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <filter id="glassFilter" colorInterpolationFilters="sRGB">
            {/* Input displacement image */}
            <feImage
              x="0"
              y="0"
              width="100%"
              height="100%"
              href={displacementImage}
              result="map"
            />
            
            {/* RED channel with displacement */}
            <feDisplacementMap
              in="SourceGraphic"
              in2="map"
              scale={scale + r}
              xChannelSelector={x}
              yChannelSelector={y}
              result="dispRed"
            />
            <feColorMatrix
              in="dispRed"
              type="matrix"
              values="1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0"
              result="red"
            />
            
            {/* GREEN channel */}
            <feDisplacementMap
              in="SourceGraphic"
              in2="map"
              scale={scale + g}
              xChannelSelector={x}
              yChannelSelector={y}
              result="dispGreen"
            />
            <feColorMatrix
              in="dispGreen"
              type="matrix"
              values="0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 1 0"
              result="green"
            />
            
            {/* BLUE channel with displacement */}
            <feDisplacementMap
              in="SourceGraphic"
              in2="map"
              scale={scale + b}
              xChannelSelector={x}
              yChannelSelector={y}
              result="dispBlue"
            />
            <feColorMatrix
              in="dispBlue"
              type="matrix"
              values="0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 1 0"
              result="blue"
            />
            
            {/* Blend channels back together */}
            <feBlend in="red" in2="green" mode="screen" result="rg" />
            <feBlend in="rg" in2="blue" mode="screen" result="output" />
            
            {/* Final blur */}
            <feGaussianBlur in="output" stdDeviation="0.7" />
          </filter>
        </defs>
      </svg>
    );
  };

  // Inicializar posición y configuración
  useEffect(() => {
    if (!containerRef.current) return;

    const container = containerRef.current;
    const { width, height, radius, frost } = currentConfig;

    // Aplicar estilos CSS
    gsap.set(container, {
      width: `${width}px`,
      height: `${height}px`,
      borderRadius: `${radius}px`,
      x: `${initialPosition.x}%`,
      y: `${initialPosition.y}%`,
      opacity: 0,
      '--frost': frost,
    });

    // Mostrar con animación
    gsap.to(container, {
      opacity: 1,
      duration: 0.3,
      ease: 'power2.out',
      onComplete: () => setIsVisible(true),
    });
  }, [currentConfig, initialPosition]);

  // Configurar draggable
  useEffect(() => {
    if (!draggable || !containerRef.current || !isVisible) return;

    const draggableInstance = Draggable.create(containerRef.current, {
      type: 'x,y',
      bounds: 'body',
      inertia: true,
      onDrag: function() {
        if (onMove) {
          const bounds = this.target.getBoundingClientRect();
          const x = (bounds.left / window.innerWidth) * 100;
          const y = (bounds.top / window.innerHeight) * 100;
          onMove(x, y);
        }
      },
    });

    return () => {
      draggableInstance[0].kill();
    };
  }, [draggable, isVisible, onMove]);

  // Actualizar configuración cuando cambie el preset
  useEffect(() => {
    const newConfig = {
      ...glassPresets[preset],
      ...config,
    };
    setCurrentConfig(newConfig);
  }, [preset, config]);

  const containerClasses = `
    fixed z-50 transition-opacity duration-300 ease-out
    ${draggable ? 'cursor-grab active:cursor-grabbing' : ''}
    ${className}
  `.trim();

  const effectStyles: React.CSSProperties = {
    width: '100%',
    height: '100%',
    overflow: 'hidden',
    borderRadius: `${currentConfig.radius}px`,
    backdropFilter: `url(#glassFilter) brightness(1.1) saturate(1.5)`,
    WebkitBackdropFilter: `url(#glassFilter) brightness(1.1) saturate(1.5)`,
    background: currentConfig.frost > 0 ? `rgba(255, 255, 255, ${currentConfig.frost})` : 'transparent',
    boxShadow: `
      0 0 2px 1px rgba(0, 0, 0, 0.15) inset,
      0 0 10px 4px rgba(0, 0, 0, 0.1) inset,
      0px 4px 16px rgba(17, 17, 26, 0.05),
      0px 8px 24px rgba(17, 17, 26, 0.05),
      0px 16px 56px rgba(17, 17, 26, 0.05),
      0px 4px 16px rgba(17, 17, 26, 0.05) inset,
      0px 8px 24px rgba(17, 17, 26, 0.05) inset,
      0px 16px 56px rgba(17, 17, 26, 0.05) inset
    `.trim(),
  };

  return (
    <div ref={containerRef} className={containerClasses}>
      {generateSVGFilter()}
      <div style={effectStyles}>
        <div className="w-full h-full flex items-center justify-center pointer-events-none">
          {children}
        </div>
      </div>
    </div>
  );
};
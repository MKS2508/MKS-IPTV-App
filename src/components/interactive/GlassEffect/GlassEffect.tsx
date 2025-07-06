/**
 * Componente GlassEffect con filtros SVG avanzados
 * Basado en https://codepen.io/mks2508/pen/QwbeKja
 */

import React, { useEffect, useRef, useState } from 'react';
import { gsap } from 'gsap';
import { Draggable } from 'gsap/Draggable';

import type { GlassEffectProps, GlassEffectState, SVGFilterProps } from './types';
import { presetConfigs, baseStyles, generateNoiseData, animationConfig } from './styles';

// Registrar plugins GSAP
gsap.registerPlugin(Draggable);

/**
 * Componente SVG Filter para efectos glass avanzados
 */
const SVGFilter: React.FC<SVGFilterProps> = ({ id, displacementScale, blurAmount }) => {
  const [noiseData, setNoiseData] = useState<string>('');

  useEffect(() => {
    // Generar ruido para el displacement map
    const noise = generateNoiseData(256, 256);
    setNoiseData(noise);
  }, []);

  return (
    <svg className={baseStyles.svg} style={{ position: 'absolute', top: 0, left: 0 }}>
      <defs>
        <filter id={id} x="-50%" y="-50%" width="200%" height="200%">
          {/* Imagen de ruido para displacement */}
          <feImage
            href={noiseData}
            result="noiseImage"
            x="0"
            y="0"
            width="100%"
            height="100%"
          />
          
          {/* Turbulencia para efectos adicionales */}
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.04 0.06"
            numOctaves="4"
            result="turbulence"
            stitchTiles="stitch"
          />
          
          {/* Displacement map principal */}
          <feDisplacementMap
            in="SourceGraphic"
            in2="turbulence"
            scale={displacementScale}
            xChannelSelector="R"
            yChannelSelector="G"
            result="displaced"
          />
          
          {/* Blur gaussiano */}
          <feGaussianBlur
            in="displaced"
            stdDeviation={blurAmount}
            result="blurred"
          />
          
          {/* Componente especular */}
          <feSpecularLighting
            in="blurred"
            result="specular"
            lightingColor="white"
            specularConstant="2"
            specularExponent="20"
          >
            <feDistantLight azimuth="45" elevation="60" />
          </feSpecularLighting>
          
          {/* Composición final */}
          <feComposite
            in="specular"
            in2="SourceAlpha"
            operator="in"
            result="specularOut"
          />
          
          <feComposite
            in="SourceGraphic"
            in2="specularOut"
            operator="arithmetic"
            k1="0"
            k2="1"
            k3="1"
            k4="0"
          />
        </filter>
      </defs>
    </svg>
  );
};

/**
 * Componente principal GlassEffect
 */
export const GlassEffect: React.FC<GlassEffectProps> = ({
  preset = 'dock',
  children,
  className = '',
  id = '',
  onDrag,
  customConfig = {},
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const glassRef = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<GlassEffectState>({
    x: 0,
    y: 0,
    isDragging: false,
    filterId: `glass-filter-${id || Math.random().toString(36).substr(2, 9)}`,
  });

  // Configuración combinada (preset + custom)
  const config = { ...presetConfigs[preset], ...customConfig };

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // Posición inicial
    const initialX = config.initialX || 0;
    const initialY = config.initialY || 0;
    
    gsap.set(container, {
      x: initialX,
      y: initialY,
      opacity: 0,
      scale: 0.9,
    });

    // Animación de entrada
    gsap.to(container, {
      opacity: 1,
      scale: 1,
      duration: animationConfig.initial.duration,
      ease: animationConfig.initial.ease,
    });

    // Configurar draggable si está habilitado
    if (config.draggable) {
      const draggable = Draggable.create(container, {
        type: 'x,y',
        bounds: 'window',
        inertia: true,
        edgeResistance: 0.8,
        onDragStart: () => {
          setState(prev => ({ ...prev, isDragging: true }));
          gsap.to(container, {
            scale: 1.05,
            duration: 0.2,
            ease: 'power2.out',
          });
        },
        onDrag: function() {
          const newX = this.x;
          const newY = this.y;
          setState(prev => ({ ...prev, x: newX, y: newY }));
          onDrag?.(newX, newY);
        },
        onDragEnd: () => {
          setState(prev => ({ ...prev, isDragging: false }));
          gsap.to(container, {
            scale: 1,
            duration: 0.3,
            ease: 'power2.out',
          });
        },
      });

      return () => {
        draggable[0]?.kill();
      };
    }
  }, [config, onDrag]);

  // Efecto hover
  useEffect(() => {
    const glass = glassRef.current;
    if (!glass) return;

    const handleMouseEnter = () => {
      gsap.to(glass, {
        scale: 1.02,
        duration: 0.3,
        ease: 'power2.out',
      });
    };

    const handleMouseLeave = () => {
      gsap.to(glass, {
        scale: 1,
        duration: 0.3,
        ease: 'power2.out',
      });
    };

    glass.addEventListener('mouseenter', handleMouseEnter);
    glass.addEventListener('mouseleave', handleMouseLeave);

    return () => {
      glass.removeEventListener('mouseenter', handleMouseEnter);
      glass.removeEventListener('mouseleave', handleMouseLeave);
    };
  }, []);

  const containerClasses = [
    baseStyles.container,
    state.isDragging ? baseStyles.dragging : '',
    className,
  ].join(' ');

  const glassStyles: React.CSSProperties = {
    width: config.width,
    height: config.height,
    borderRadius: config.borderRadius,
    borderColor: config.borderColor,
    borderWidth: config.borderWidth,
    backgroundColor: `rgba(255, 255, 255, ${config.backgroundOpacity})`,
    filter: `url(#${state.filterId})`,
    backdropFilter: `blur(${config.blurAmount}px) saturate(1.5)`,
  };

  return (
    <div
      ref={containerRef}
      className={containerClasses}
      style={{
        width: config.width,
        height: config.height,
        cursor: config.draggable ? (state.isDragging ? 'grabbing' : 'grab') : 'default',
      }}
    >
      {/* Filtros SVG */}
      <SVGFilter
        id={state.filterId}
        displacementScale={config.displacementScale}
        blurAmount={config.blurAmount}
      />
      
      {/* Elemento glass principal */}
      <div
        ref={glassRef}
        className={baseStyles.glassElement}
        style={glassStyles}
      />
      
      {/* Contenido */}
      <div className={baseStyles.content}>
        {children || (
          <div className="text-white/80 font-medium">
            Glass Effect - {preset.charAt(0).toUpperCase() + preset.slice(1)}
          </div>
        )}
      </div>
    </div>
  );
};

export default GlassEffect;
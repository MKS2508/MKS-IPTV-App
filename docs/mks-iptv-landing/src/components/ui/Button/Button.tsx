/**
 * @file Componente React Button universal con Framer Motion.
 * @author MKS
 */

import React, { forwardRef, useMemo } from 'react';
import { motion } from 'framer-motion';
import * as LucideIcons from 'lucide-react';
import type { UniversalButtonProps } from './types';
import { buttonStyles } from './styles';

export const Button = forwardRef<
  HTMLButtonElement | HTMLAnchorElement,
  UniversalButtonProps & { motionConfigSerialized?: string }
>((props, ref) => {
  const {
    children,
    text,
    variant = 'primary',
    size = 'md',
    width = 'auto',
    icon,
    loading = false,
    disabled = false,
    className = '',
    motion: motionConfig,
    motionConfigSerialized,
    id,
    ...restProps
  } = props;

  // Determinar si es un link o botón
  const isLink = props.as === 'link';
  const MotionComponent = isLink ? motion.a : motion.button;

  // Configuración de animaciones Framer Motion
  const defaultMotion = buttonStyles.motionPresets.gentle;
  
  // Deserializar motionConfig desde Astro
  let deserializedMotionConfig;
  try {
    deserializedMotionConfig = motionConfigSerialized ? JSON.parse(motionConfigSerialized) : null;
  } catch (e) {
    deserializedMotionConfig = null;
  }
  
  // Usar la configuración deserializada o la que viene directamente
  const activeMotionConfig = deserializedMotionConfig || motionConfig;

  // Construir clases CSS
  const classes = useMemo(() => {
    const variantStyles = buttonStyles.variants[variant];
    const sizeStyles = buttonStyles.sizes[size];
    const widthStyle = buttonStyles.widths[width];

    return [
      // Base sin transiciones CSS si tiene motion personalizado
      activeMotionConfig ? buttonStyles.baseNoTransition : buttonStyles.base,
      variantStyles.background,
      variantStyles.text,
      variantStyles.border,
      variantStyles.shadow,
      variantStyles.focus,
      sizeStyles.padding,
      sizeStyles.text,
      sizeStyles.height,
      sizeStyles.gap,
      sizeStyles.rounded,
      widthStyle,
      loading ? buttonStyles.states.loading : '',
      disabled ? buttonStyles.states.disabled : '',
      buttonStyles.effects.shimmer,
      className
    ].filter(Boolean).join(' ');
  }, [variant, size, width, loading, disabled, className, activeMotionConfig]);
  
  // Transformar motionConfig de Astro a formato Framer Motion
  const transformedMotion = activeMotionConfig ? {
    whileHover: activeMotionConfig.hover,
    whileTap: activeMotionConfig.tap,
    initial: activeMotionConfig.initial,
    animate: activeMotionConfig.animate,
    transition: { type: "spring", stiffness: 300, damping: 12 }
  } : {};
  
  const finalMotionConfig = {
    ...defaultMotion,
    ...transformedMotion
  };


  // Renderizar icono
  const renderIcon = () => {
    if (!icon) return null;

    const iconSize = buttonStyles.icon.sizes[size];
    const iconClasses = [
      iconSize,
      icon.className || '',
      icon.position === 'only' ? buttonStyles.icon.positions.only : 
      icon.position === 'right' ? buttonStyles.icon.positions.right : 
      buttonStyles.icon.positions.left
    ].filter(Boolean).join(' ');

    // Icono de Lucide
    if (icon.lucide) {
      const LucideIcon = LucideIcons[icon.lucide as keyof typeof LucideIcons] as React.ComponentType<any>;
      if (LucideIcon) {
        return (
          <LucideIcon 
            className={iconClasses}
            size={icon.size}
            aria-hidden="true"
          />
        );
      }
    }

    // Icono de Simple Icons (implementación temporal)
    if (icon.simple) {
      // Mapeo básico de algunos iconos populares
      const simpleIconsPaths = {
        apple: 'M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09z',
        github: 'M12 .5C5.37.5 0 5.78 0 12.292c0 5.211 3.438 9.63 8.205 11.188.6.111.82-.254.82-.567 0-.28-.01-1.022-.015-2.005-3.338.711-4.042-1.582-4.042-1.582-.546-1.361-1.335-1.725-1.335-1.725-1.087-.731.084-.716.084-.716 1.205.082 1.838 1.215 1.838 1.215 1.07 1.803 2.809 1.282 3.495.981.108-.763.417-1.282.76-1.577-2.665-.295-5.466-1.309-5.466-5.827 0-1.287.465-2.339 1.235-3.164-.135-.298-.54-1.497.105-3.121 0 0 1.005-.316 3.3 1.209.96-.262 1.98-.392 3-.398 1.02.006 2.04.136 3 .398 2.28-1.525 3.285-1.209 3.285-1.209.645 1.624.24 2.823.12 3.121.765.825 1.23 1.877 1.23 3.164 0 4.53-2.805 5.527-5.479 5.817.42.354.81 1.077.81 2.182 0 1.578-.015 2.846-.015 3.229 0 .309.21.678.825.56C20.565 21.917 24 17.495 24 12.292 24 5.78 18.627.5 12 .5z',
        react: 'M14.23 12.004a2.236 2.236 0 0 1-2.235 2.236 2.236 2.236 0 0 1-2.236-2.236 2.236 2.236 0 0 1 2.235-2.236 2.236 2.236 0 0 1 2.236 2.236zm2.648-10.69c-1.346 0-3.107.96-4.888 2.622-1.78-1.653-3.542-2.602-4.887-2.602-.41 0-.783.093-1.106.278-1.375.793-1.683 3.264-.973 6.365C1.98 8.917 0 10.42 0 12.004c0 1.59 1.99 3.097 5.043 4.03-.704 3.113-.39 5.588.988 6.38.32.187.69.275 1.102.275 1.345 0 3.107-.96 4.888-2.624 1.78 1.654 3.542 2.603 4.887 2.603.41 0 .783-.09 1.106-.275 1.374-.792 1.683-3.263.973-6.365C22.02 15.096 24 13.59 24 12.004c0-1.59-1.99-3.097-5.043-4.032.704-3.11.39-5.587-.988-6.38-.318-.184-.688-.277-1.092-.275z'
      };
      
      const pathData = simpleIconsPaths[icon.simple as keyof typeof simpleIconsPaths];
      if (pathData) {
        return (
          <svg
            className={iconClasses}
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
            style={{
              width: icon.size || undefined,
              height: icon.size || undefined
            }}
          >
            <path d={pathData} />
          </svg>
        );
      }
    }

    return null;
  };

  // Spinner de carga
  const renderSpinner = () => {
    if (!loading) return null;

    const spinnerSize = buttonStyles.icon.sizes[size];
    
    return (
      <svg
        className={`animate-spin ${spinnerSize}`}
        fill="none"
        viewBox="0 0 24 24"
        aria-hidden="true"
      >
        <circle
          className="opacity-25"
          cx="12"
          cy="12"
          r="10"
          stroke="currentColor"
          strokeWidth="4"
        />
        <path
          className="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
        />
      </svg>
    );
  };

  // Props específicos para links
  const linkProps = isLink ? {
    href: (props as any).href,
    target: (props as any).external ? '_blank' : undefined,
    rel: (props as any).external ? 'noopener noreferrer' : undefined
  } : {};

  // Props específicos para botones
  const buttonProps = !isLink ? {
    type: (restProps as any).type || 'button',
    disabled: disabled || loading
  } : {};

  // Separar restProps para evitar conflictos de tipos
  const {
    as: _as,
    href: _href,
    external: _external,
    motionConfig: _motionConfig,
    variant: _variant,
    size: _size,
    width: _width,
    icon: _icon,
    loading: _loading,
    motion: _motion,
    ...cleanRestProps
  } = restProps as any;

  // Determinar el contenido a mostrar
  const buttonText = text || children;

  // Contenido del botón
  const content = (
    <>
      {loading && renderSpinner()}
      {!loading && icon && icon.position !== 'right' && renderIcon()}
      {icon?.position !== 'only' && buttonText && (
        <span className={loading ? 'opacity-0' : ''}>
          {buttonText}
        </span>
      )}
      {!loading && icon && icon.position === 'right' && renderIcon()}
    </>
  );

  return (
    <MotionComponent
      ref={ref as any}
      id={id}
      className={classes}
      aria-disabled={disabled || loading}
      {...finalMotionConfig}
      {...linkProps}
      {...buttonProps}
      {...cleanRestProps}
      style={(restProps as any).style}
    >
      {content}
    </MotionComponent>
  );
});

Button.displayName = 'Button';
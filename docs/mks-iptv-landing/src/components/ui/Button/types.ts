/**
 * @file Tipos para el componente Button universal.
 * @author MKS
 */

import type { ReactNode, ButtonHTMLAttributes, AnchorHTMLAttributes } from 'react';
import type { Variants, Transition } from 'framer-motion';

export type ButtonVariant = 
  | 'primary' 
  | 'secondary' 
  | 'outline' 
  | 'ghost' 
  | 'danger' 
  | 'success'
  | 'highlight';

export type ButtonSize = 'sm' | 'md' | 'lg' | 'xl';

export type IconPosition = 'left' | 'right' | 'only';

export type ButtonWidth = 'auto' | 'full' | 'fit';

// Iconos de Lucide React (nombres reales)
export type LucideIconName = 
  | 'Download' 
  | 'Info' 
  | 'Play' 
  | 'ExternalLink'
  | 'ChevronRight'
  | 'ChevronDown'
  | 'Check'
  | 'X'
  | 'Plus'
  | 'Minus'
  | 'Search'
  | 'Menu'
  | 'Settings'
  | 'User'
  | 'Home'
  | 'Star'
  | 'Heart'
  | 'Eye'
  | 'Share'
  | 'Copy'
  | 'Edit'
  | 'Trash2'
  | 'ArrowRight'
  | 'ArrowLeft'
  | 'ArrowUp'
  | 'ArrowDown'
  | 'Image'
  | 'BookOpen';

// Iconos de Simple Icons (nombres de slug)
export type SimpleIconName = 
  | 'apple'
  | 'github' 
  | 'twitter'
  | 'youtube'
  | 'discord'
  | 'instagram'
  | 'facebook'
  | 'linkedin'
  | 'google'
  | 'microsoft'
  | 'amazon'
  | 'netflix'
  | 'spotify'
  | 'twitch'
  | 'reddit'
  | 'telegram'
  | 'whatsapp'
  | 'slack'
  | 'notion'
  | 'figma'
  | 'vercel'
  | 'nextdotjs'
  | 'react'
  | 'typescript'
  | 'javascript'
  | 'nodejs'
  | 'bun'
  | 'astro';

export interface ButtonMotionConfig {
  /** Variantes de animación personalizada */
  variants?: Variants;
  /** Configuración de transición */
  transition?: Transition;
  /** Animación al hacer hover */
  whileHover?: any;
  /** Animación al hacer tap/click */
  whileTap?: any;
  /** Animación al entrar */
  initial?: any;
  /** Animación final */
  animate?: any;
  /** Animación al salir */
  exit?: any;
}

export interface ButtonIconConfig {
  /** Nombre del icono de Lucide */
  lucide?: LucideIconName;
  /** Nombre del icono de Simple Icons */
  simple?: SimpleIconName;
  /** Posición del icono */
  position?: IconPosition;
  /** Tamaño del icono (override del size del botón) */
  size?: number;
  /** Clases adicionales para el icono */
  className?: string;
}

interface BaseButtonProps {
  /** Contenido del botón */
  children?: ReactNode;
  /** Texto del botón (alternativa a children para Astro) */
  text?: string;
  /** Variante de estilo */
  variant?: ButtonVariant;
  /** Tamaño del botón */
  size?: ButtonSize;
  /** Ancho del botón */
  width?: ButtonWidth;
  /** Configuración del icono */
  icon?: ButtonIconConfig;
  /** Estado de carga */
  loading?: boolean;
  /** Estado deshabilitado */
  disabled?: boolean;
  /** Clases CSS adicionales */
  className?: string;
  /** Configuración de animaciones Framer Motion */
  motion?: ButtonMotionConfig;
  /** ID único */
  id?: string;
}

// Props para botón tipo button
export interface ButtonProps extends BaseButtonProps, 
  Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'className' | 'disabled' | 'children'> {
  /** Tipo de elemento (button por defecto) */
  as?: 'button';
}

// Props para botón tipo link
export interface LinkButtonProps extends BaseButtonProps,
  Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'className' | 'children'> {
  /** Tipo de elemento (link) */
  as: 'link';
  /** URL de destino */
  href: string;
  /** Abrir en nueva pestaña */
  external?: boolean;
}

// Tipo unión para ambos casos
export type UniversalButtonProps = ButtonProps | LinkButtonProps;

// Props para el wrapper de Astro
export interface AstroButtonProps extends Omit<UniversalButtonProps, 'motion'> {
  /** Configuración de animaciones serializable */
  motionConfig?: {
    hover?: Record<string, any>;
    tap?: Record<string, any>;
    initial?: Record<string, any>;
    animate?: Record<string, any>;
  } | undefined;
  /** URL de destino para links */
  href?: string;
  /** Abrir en nueva pestaña */
  external?: boolean;
}
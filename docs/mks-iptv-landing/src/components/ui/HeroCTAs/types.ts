/**
 * Tipos para el componente HeroCTAs
 * Maneja los botones de Call-to-Action del Hero con interacciones mejoradas
 */

export interface CTAButton {
  /** Texto del botón */
  text: string;
  /** URL de destino */
  href: string;
  /** Variante de estilo */
  variant?: 'primary' | 'secondary' | 'outline' | 'ghost';
  /** Icono opcional (nombre o SVG) */
  icon?: string;
  /** Abrir en nueva pestaña */
  external?: boolean;
  /** Deshabilitado */
  disabled?: boolean;
  /** ID único para tracking */
  id?: string;
}

export interface HeroCTAsProps {
  /** Array de botones CTA */
  buttons?: CTAButton[];
  /** Mostrar animaciones GSAP */
  animated?: boolean;
  /** Layout de los botones */
  layout?: 'horizontal' | 'vertical' | 'stacked';
  /** Clases CSS adicionales para el container */
  className?: string;
  /** ID único para targeting de animaciones */
  id?: string;
}
/**
 * Tipos para el componente HeroTitle
 * Maneja title y subtitle del Hero con hierarchy mejorada
 */

export interface HeroTitleProps {
  /** Título principal */
  title?: string;
  /** Subtítulo/versión */
  subtitle?: string;
  /** Mostrar animaciones GSAP */
  animated?: boolean;
  /** Clases CSS adicionales para el container */
  className?: string;
  /** Clases CSS adicionales para el título */
  titleClassName?: string;
  /** Clases CSS adicionales para el subtítulo */
  subtitleClassName?: string;
  /** ID único para targeting de animaciones */
  id?: string;
}
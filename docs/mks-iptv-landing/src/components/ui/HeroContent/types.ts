/**
 * Tipos para el componente HeroContent
 * Maneja descripción, tagline y contenido adicional del Hero
 */

export interface HeroContentProps {
  /** Descripción principal */
  description?: string;
  /** Tagline o slogan */
  tagline?: string;
  /** Características destacadas */
  features?: string[];
  /** Mostrar animaciones GSAP */
  animated?: boolean;
  /** Alineación del contenido */
  alignment?: 'left' | 'center' | 'right';
  /** Clases CSS adicionales para el container */
  className?: string;
  /** Clases CSS adicionales para la descripción */
  descriptionClassName?: string;
  /** Clases CSS adicionales para el tagline */
  taglineClassName?: string;
  /** ID único para targeting de animaciones */
  id?: string;
}
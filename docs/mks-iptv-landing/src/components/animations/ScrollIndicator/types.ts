/**
 * Tipos para el componente ScrollIndicator
 * Indicador de scroll elegante con animaciones GSAP integradas
 */

export interface ScrollIndicatorProps {
  /** Texto del indicador de scroll */
  text?: string;
  /** Si debe mostrar la línea animada */
  showLine?: boolean;
  /** Si debe mostrar el glow effect */
  showGlow?: boolean;
  /** Clases CSS adicionales */
  className?: string;
  /** ID único para el componente */
  id?: string;
  /** Callback cuando el componente se oculta */
  onHide?: () => void;
}
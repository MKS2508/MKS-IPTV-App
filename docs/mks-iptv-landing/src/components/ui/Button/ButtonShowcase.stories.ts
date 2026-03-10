/**
 * @file Stories del ButtonShowcase - Sistema de Animación Híbrido Profesional
 * @description 4 stories consolidadas que demuestran el sistema completo
 * @author MKS
 */

import type { ComponentProps } from 'astro/types'
import ButtonShowcase from './ButtonShowcase.astro'

type ButtonShowcaseProps = ComponentProps<typeof ButtonShowcase>

export default {
  component: ButtonShowcase,
}

// ===== STORIES PROFESIONALES CONSOLIDADAS =====

/**
 * Vista completa profesional
 * Muestra todo el sistema de animación híbrido con indicadores de configuración
 */
export const Complete = {
  args: {
    section: 'all',
  } satisfies ButtonShowcaseProps,
}

/**
 * Comparativa de motores de animación
 * Comparación técnica entre Framer Motion, GSAP y CSS Transitions
 */
export const AnimationEngines = {
  args: {
    section: 'engines',
  } satisfies ButtonShowcaseProps,
}

/**
 * Contextos optimizados para casos reales
 * Hero CTAs, Form buttons, Navigation y optimizaciones automáticas
 */
export const ContextOptimized = {
  args: {
    section: 'animations',
  } satisfies ButtonShowcaseProps,
}

/**
 * Guía de implementación básica
 * Variantes fundamentales con configuración por defecto y ejemplos
 */
export const ImplementationGuide = {
  args: {
    section: 'variants',
  } satisfies ButtonShowcaseProps,
}
import type { ComponentProps } from 'astro/types'
import Hero from './index.astro'
import { getImagePath } from '../../../utils/image-paths'
import { banners } from '../../../data/assets'

type HeroProps = ComponentProps<typeof Hero>

export default {
  component: Hero,
  title: 'Sections/Hero',
}

export const Default = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    enableScrollAnimations: true,
    showParticles: true,
  } satisfies HeroProps,
}

export const NoParticles = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    showParticles: false,
  } satisfies HeroProps,
}

export const NoScrollAnimations = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    enableScrollAnimations: false,
  } satisfies HeroProps,
}

export const NoBackground = {
  args: {
    showParticles: true,
  } satisfies HeroProps,
}

export const CustomContent = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    title: 'Tu Streaming Favorito',
    subtitle: 'v3.0 Beta',
    description: 'La mejor experiencia de IPTV en dispositivos Apple',
    tagline: 'Optimizado para iOS 18, macOS 15 y tvOS 18',
    ctaPrimaryText: 'Instalar Ahora',
    ctaSecondaryText: 'Ver Demo',
    ctaTertiaryText: 'Guía Rápida',
  } satisfies HeroProps,
}
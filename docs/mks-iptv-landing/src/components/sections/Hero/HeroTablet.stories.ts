import type { ComponentProps } from 'astro/types'
import HeroTabletWrapper from './HeroTabletWrapper.astro'
import { getImagePath } from '../../../utils/image-paths'
import { banners } from '../../../data/assets'

type HeroProps = ComponentProps<typeof HeroTabletWrapper>

export default {
  component: HeroTabletWrapper,
  title: 'Sections/Hero/Tablet',
}

export const Default = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
  } satisfies HeroProps,
}

export const NoParticles = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    showParticles: false,
  } satisfies HeroProps,
}

export const CustomContent = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    title: 'MKS-IPTV para iPad',
    subtitle: 'Experiencia Premium',
    description: 'Diseñado específicamente para la pantalla del iPad',
    tagline: 'Compatible con iPad Pro, Air y Mini',
  } satisfies HeroProps,
}
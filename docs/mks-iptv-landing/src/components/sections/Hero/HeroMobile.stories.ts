import type { ComponentProps } from 'astro/types'
import HeroMobileWrapper from './HeroMobileWrapper.astro'
import { getImagePath } from '../../../utils/image-paths'
import { banners } from '../../../data/assets'

type HeroProps = ComponentProps<typeof HeroMobileWrapper>

export default {
  component: HeroMobileWrapper,
  title: 'Sections/Hero/Mobile',
}

export const Default = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
  } satisfies HeroProps,
}

export const CustomContent = {
  args: {
    backgroundImage: getImagePath(banners.hero.src),
    title: 'MKS-IPTV Mobile',
    subtitle: 'v2.5.0',
    description: 'Optimizado para iPhone',
    showParticles: false,
  } satisfies HeroProps,
}
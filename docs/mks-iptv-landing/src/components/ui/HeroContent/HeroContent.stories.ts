import type { ComponentProps } from 'astro/types';
import HeroContent from './index.astro';

type HeroContentProps = ComponentProps<typeof HeroContent>;

export default {
  component: HeroContent,
  title: 'UI/HeroContent',
};

export const Default = {
  args: {
    animated: true,
    alignment: 'center',
  } satisfies HeroContentProps,
};

export const CustomContent = {
  args: {
    description: 'Experimenta el streaming de televisión más avanzado con tecnología de última generación y una interfaz diseñada para la máxima comodidad.',
    tagline: 'El futuro del entretenimiento, hoy',
    features: [
      'Streaming 4K HDR',
      'Dolby Atmos',
      'Sin Buffering',
      'Multiplataforma'
    ],
    animated: true,
    alignment: 'center',
  } satisfies HeroContentProps,
};

export const LeftAligned = {
  args: {
    alignment: 'left',
    animated: true,
  } satisfies HeroContentProps,
};

export const RightAligned = {
  args: {
    alignment: 'right',
    animated: true,
  } satisfies HeroContentProps,
};

export const WithoutFeatures = {
  args: {
    description: 'Una aplicación IPTV revolucionaria que cambiará tu forma de ver televisión.',
    tagline: 'Streaming sin límites',
    features: [],
    animated: true,
    alignment: 'center',
  } satisfies HeroContentProps,
};

export const OnlyDescription = {
  args: {
    description: 'Disfruta de miles de canales, películas y series en la máxima calidad.',
    tagline: '',
    features: [],
    animated: true,
    alignment: 'center',
  } satisfies HeroContentProps,
};

export const MinimalFeatures = {
  args: {
    description: 'La mejor experiencia IPTV.',
    tagline: 'Simple. Rápido. Efectivo.',
    features: [
      '4K',
      'Gratis',
      'Sin Ads'
    ],
    animated: true,
    alignment: 'center',
  } satisfies HeroContentProps,
};

export const ExtendedFeatures = {
  args: {
    description: 'Una solución completa de entretenimiento que incluye todo lo que necesitas.',
    tagline: 'Todo en uno, sin complicaciones',
    features: [
      'Streaming 4K',
      'Descarga Offline',
      'Control Parental',
      'Multi-Idioma',
      'Chromecast',
      'AirPlay',
      'Smart TV',
      'Móvil'
    ],
    animated: true,
    alignment: 'center',
  } satisfies HeroContentProps,
};

export const WithoutAnimation = {
  args: {
    animated: false,
    alignment: 'center',
  } satisfies HeroContentProps,
};
import type { ComponentProps } from 'astro/types';
import HeroCTAs from './index.astro';

type HeroCTAsProps = ComponentProps<typeof HeroCTAs>;

export default {
  component: HeroCTAs,
  title: 'UI/HeroCTAs',
};

export const Default = {
  args: {
    animated: true,
    layout: 'stacked',
  } satisfies HeroCTAsProps,
};

export const Horizontal = {
  args: {
    animated: true,
    layout: 'horizontal',
  } satisfies HeroCTAsProps,
};

export const Vertical = {
  args: {
    animated: true,
    layout: 'vertical',
  } satisfies HeroCTAsProps,
};

export const CustomButtons = {
  args: {
    buttons: [
      {
        text: 'Descargar Ahora',
        href: '#download',
        variant: 'primary',
        icon: 'download',
        id: 'custom-download'
      },
      {
        text: 'Ver Demo',
        href: '#demo',
        variant: 'secondary',
        icon: 'play',
        id: 'custom-demo'
      },
      {
        text: 'GitHub',
        href: 'https://github.com',
        variant: 'outline',
        icon: 'external',
        external: true,
        id: 'custom-github'
      }
    ],
    animated: true,
    layout: 'horizontal',
  } satisfies HeroCTAsProps,
};

export const SingleButton = {
  args: {
    buttons: [
      {
        text: 'Comenzar',
        href: '#start',
        variant: 'primary',
        icon: 'download',
        id: 'single-btn'
      }
    ],
    animated: true,
    layout: 'horizontal',
  } satisfies HeroCTAsProps,
};

export const AllVariants = {
  args: {
    buttons: [
      {
        text: 'Primary',
        href: '#primary',
        variant: 'primary',
        icon: 'download',
        id: 'variant-primary'
      },
      {
        text: 'Secondary',
        href: '#secondary',
        variant: 'secondary',
        icon: 'info',
        id: 'variant-secondary'
      },
      {
        text: 'Outline',
        href: '#outline',
        variant: 'outline',
        icon: 'play',
        id: 'variant-outline'
      },
      {
        text: 'Ghost',
        href: '#ghost',
        variant: 'ghost',
        icon: 'external',
        id: 'variant-ghost'
      }
    ],
    animated: true,
    layout: 'horizontal',
  } satisfies HeroCTAsProps,
};

export const WithoutAnimation = {
  args: {
    animated: false,
    layout: 'stacked',
  } satisfies HeroCTAsProps,
};

export const DisabledState = {
  args: {
    buttons: [
      {
        text: 'Descargar',
        href: '#download',
        variant: 'primary',
        icon: 'download',
        disabled: true,
        id: 'disabled-btn'
      },
      {
        text: 'Más Info',
        href: '#info',
        variant: 'outline',
        icon: 'info',
        id: 'enabled-btn'
      }
    ],
    animated: true,
    layout: 'horizontal',
  } satisfies HeroCTAsProps,
};
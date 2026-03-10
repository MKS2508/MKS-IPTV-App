import type { ComponentProps } from 'astro/types';
import HeroTitle from './index.astro';

type HeroTitleProps = ComponentProps<typeof HeroTitle>;

export default {
  component: HeroTitle,
  title: 'UI/HeroTitle',
};

export const Default = {
  args: {
    title: 'MKS IPTV',
    subtitle: 'v2.5.1',
    animated: true,
  } satisfies HeroTitleProps,
};

export const WithoutSubtitle = {
  args: {
    title: 'MKS IPTV',
    animated: true,
  } satisfies HeroTitleProps,
};

export const WithoutAnimation = {
  args: {
    title: 'MKS IPTV',
    subtitle: 'v2.5.1',
    animated: false,
  } satisfies HeroTitleProps,
};

export const CustomText = {
  args: {
    title: 'Streaming Experience',
    subtitle: 'Next Generation',
    animated: true,
  } satisfies HeroTitleProps,
};

export const LongTitle = {
  args: {
    title: 'Multi-Platform IPTV Streaming Application',
    subtitle: 'Professional Edition v2.5.1',
    animated: true,
  } satisfies HeroTitleProps,
};

export const CustomStyling = {
  args: {
    title: 'MKS IPTV',
    subtitle: 'v2.5.1',
    animated: true,
    className: 'custom-hero-title',
    titleClassName: 'text-app-accent',
    subtitleClassName: 'text-app-highlight',
  } satisfies HeroTitleProps,
};
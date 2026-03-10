
export interface HeroProps {
  title?: string;
  subtitle?: string;
  description?: string;
  tagline?: string;
  ctaPrimaryText?: string;
  ctaPrimaryLink?: string;
  ctaSecondaryText?: string;
  ctaSecondaryLink?: string;
  ctaTertiaryText?: string;
  ctaTertiaryLink?: string;
  showParticles?: boolean;
  enableScrollAnimations?: boolean;
  className?: string;
  backgroundImage?: string;
}

export interface HeroAnimation {
  timeline: gsap.core.Timeline;
  scrollTrigger?: ScrollTrigger;
}

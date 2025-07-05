/**
 * Tipos e interfaces para el componente Footer.
 * Define la estructura de enlaces, redes sociales y badges.
 */

export interface FooterLink {
  label: string;
  href: string;
  isExternal?: boolean;
  icon?: string;
}

export interface SocialMedia {
  name: string;
  href: string;
  icon: string;
  ariaLabel: string;
}

export interface AppStoreBadge {
  platform: 'ios' | 'mac' | 'testflight';
  href: string;
  imageSrc: string;
  imageAlt: string;
  available: boolean;
}

export interface FooterSection {
  title: string;
  links: FooterLink[];
}

export interface FooterProps {
  showSocial?: boolean;
  showAppBadges?: boolean;
  showNewsletter?: boolean;
  className?: string;
}
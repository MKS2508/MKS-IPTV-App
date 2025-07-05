/**
 * Asset paths and metadata for MKS-IPTV-App landing page
 * Centralized asset management for consistent usage across components
 */

export interface Asset {
  id: string;
  src: string;
  alt: string;
  title?: string;
  width?: number;
  height?: number;
  format: 'webp' | 'png' | 'svg' | 'mp4';
  loading?: 'eager' | 'lazy';
}

/**
 * App logos and branding assets
 */
export const logos: Record<string, Asset> = {
  appLogo: {
    id: 'app-logo',
    src: '/images/logos/applogo.webp',
    alt: 'MKS-IPTV App Logo',
    title: 'MKS-IPTV',
    width: 120,
    height: 120,
    format: 'webp',
    loading: 'eager'
  }
};

/**
 * Hero banners and marketing images
 */
export const banners: Record<string, Asset> = {
  hero: {
    id: 'hero-banner',
    src: '/images/banners/banner3.webp',
    alt: 'MKS-IPTV App Hero Banner',
    title: 'Tu cliente IPTV multiplataforma',
    width: 1920,
    height: 1080,
    format: 'webp',
    loading: 'eager'
  },
  heroPng: {
    id: 'hero-banner-png',
    src: '/images/banners/banner3.png',
    alt: 'MKS-IPTV App Hero Banner',
    title: 'Tu cliente IPTV multiplataforma',
    width: 1920,
    height: 1080,
    format: 'png',
    loading: 'eager'
  },
  secondary: {
    id: 'secondary-banner',
    src: '/images/banners/banner4.webp',
    alt: 'MKS-IPTV App Secondary Banner',
    title: 'Streaming de alta calidad',
    width: 1920,
    height: 1080,
    format: 'webp',
    loading: 'lazy'
  },
  secondaryPng: {
    id: 'secondary-banner-png',
    src: '/images/banners/banner4.png',
    alt: 'MKS-IPTV App Secondary Banner',
    title: 'Streaming de alta calidad',
    width: 1920,
    height: 1080,
    format: 'png',
    loading: 'lazy'
  }
};

/**
 * Device frames for mockups
 */
export const frames: Record<string, Asset> = {
  iphone: {
    id: 'iphone-frame',
    src: '/images/frames/iphone-frame.svg',
    alt: 'iPhone Frame Mockup',
    title: 'iPhone Frame',
    width: 300,
    height: 600,
    format: 'svg',
    loading: 'lazy'
  },
  iphonePng: {
    id: 'iphone-frame-png',
    src: '/images/frames/marco_iphone.png',
    alt: 'iPhone Frame Mockup',
    title: 'iPhone Frame',
    width: 300,
    height: 600,
    format: 'png',
    loading: 'lazy'
  }
};

/**
 * Demo videos
 */
export const videos: Record<string, Asset> = {
  iosDemo: {
    id: 'ios-demo',
    src: '/videos/ios-demo.mp4',
    alt: 'Demostración de MKS-IPTV en iOS',
    title: 'Demo iOS',
    width: 390,
    height: 844,
    format: 'mp4',
    loading: 'lazy'
  }
};

/**
 * Favicon assets
 */
export const favicons = {
  ico: '/favicon/favicon.ico',
  svg: '/favicon.svg',
  png16: '/favicon/favicon-16x16.png',
  png32: '/favicon/favicon-32x32.png',
  appleTouchIcon: '/favicon/apple-touch-icon.png',
  androidChrome192: '/favicon/android-chrome-192x192.png',
  androidChrome512: '/favicon/android-chrome-512x512.png',
  manifest: '/favicon/site.webmanifest'
};

/**
 * Get all assets by category
 */
export const assets = {
  logos,
  banners,
  frames,
  videos,
  favicons
};

/**
 * Helper function to get responsive image sources
 */
export function getResponsiveImageSources(asset: Asset, sizes: number[] = [400, 800, 1200]) {
  return sizes.map(size => ({
    src: asset.src,
    width: size,
    media: `(max-width: ${size}px)`
  }));
}

/**
 * Helper function to get WebP with PNG fallback
 */
export function getImageWithFallback(webpAsset: Asset, pngAsset: Asset) {
  return {
    webp: webpAsset,
    fallback: pngAsset
  };
}
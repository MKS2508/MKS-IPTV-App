/**
 * Screenshot data for the MKS-IPTV-App gallery
 * Organized by platform with metadata for gallery components
 */

export interface Screenshot {
  id: string;
  src: string;
  alt: string;
  title: string;
  platform: 'ios' | 'macos' | 'tvos';
  category: 'interface' | 'downloads' | 'series' | 'movies' | 'settings';
  width: number;
  height: number;
  order: number;
}

export const screenshots: Screenshot[] = [
  // iOS Screenshots
  {
    id: 'ios-loading',
    src: '/images/screenshots/ios/ios_loadingscreen.webp',
    alt: 'Pantalla de carga de MKS-IPTV en iOS',
    title: 'Pantalla de Carga iOS',
    platform: 'ios',
    category: 'interface',
    width: 390,
    height: 844,
    order: 1
  },
  {
    id: 'ios-series-detail',
    src: '/images/screenshots/ios/ios_seriedetail.webp',
    alt: 'Vista detalle de serie en iOS',
    title: 'Detalle de Serie iOS',
    platform: 'ios',
    category: 'series',
    width: 390,
    height: 844,
    order: 2
  },
  {
    id: 'ios-series-search',
    src: '/images/screenshots/ios/ios_serielistsearch.webp',
    alt: 'Búsqueda de series en iOS',
    title: 'Búsqueda de Series iOS',
    platform: 'ios',
    category: 'series',
    width: 390,
    height: 844,
    order: 3
  },
  {
    id: 'ios-download-modal',
    src: '/images/screenshots/ios/ios_seriemodaldownload.webp',
    alt: 'Modal de descarga de serie en iOS',
    title: 'Modal de Descarga iOS',
    platform: 'ios',
    category: 'downloads',
    width: 390,
    height: 844,
    order: 4
  },
  
  // macOS Screenshots
  {
    id: 'macos-downloads',
    src: '/images/screenshots/macos/DownloadsSection_1.png',
    alt: 'Sección de descargas en macOS',
    title: 'Descargas macOS',
    platform: 'macos',
    category: 'downloads',
    width: 1200,
    height: 800,
    order: 5
  },
  {
    id: 'macos-download-modal',
    src: '/images/screenshots/macos/download_modal.png',
    alt: 'Modal de descarga en macOS',
    title: 'Modal de Descarga macOS',
    platform: 'macos',
    category: 'downloads',
    width: 1200,
    height: 800,
    order: 6
  },
  {
    id: 'macos-liquid-glass-topbar',
    src: '/images/screenshots/macos/listview_liquidglasstopbar.png',
    alt: 'Vista de lista con topbar Liquid Glass en macOS',
    title: 'Liquid Glass Interface macOS',
    platform: 'macos',
    category: 'interface',
    width: 1200,
    height: 800,
    order: 7
  },
  {
    id: 'macos-series-detail',
    src: '/images/screenshots/macos/seriesdetail_1.png',
    alt: 'Vista detalle de serie en macOS',
    title: 'Detalle de Serie macOS',
    platform: 'macos',
    category: 'series',
    width: 1200,
    height: 800,
    order: 8
  }
];

/**
 * Filter screenshots by platform
 */
export function getScreenshotsByPlatform(platform: Screenshot['platform']): Screenshot[] {
  return screenshots.filter(screenshot => screenshot.platform === platform);
}

/**
 * Filter screenshots by category
 */
export function getScreenshotsByCategory(category: Screenshot['category']): Screenshot[] {
  return screenshots.filter(screenshot => screenshot.category === category);
}

/**
 * Get featured screenshots for hero section
 */
export function getFeaturedScreenshots(): Screenshot[] {
  return screenshots.filter(screenshot => 
    ['ios-series-detail', 'macos-liquid-glass-topbar', 'ios-loading'].includes(screenshot.id)
  ).sort((a, b) => a.order - b.order);
}
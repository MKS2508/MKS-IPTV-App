/**
 * Utility to handle image paths for both development and production
 * Always uses the base path /MKS-IPTV-App since it's configured in astro.config.mjs
 */

export function getImagePath(imagePath: string): string {
  // Always use the base path since it's configured in astro.config.mjs
  return `/MKS-IPTV-App${imagePath}`;
}

// Pre-defined screenshot paths for easy reference
export const screenshots = {
  macos: {
    liquidGlass: '/imgs/v0.0.1-alpha/macos/listview_liquidglasstopbar.png',
    downloads: '/imgs/v0.0.1-alpha/macos/DownloadsSection_1.png',
    seriesDetail: '/imgs/v0.0.1-alpha/macos/seriesdetail_1.png',
    downloadModal: '/imgs/v0.0.1-alpha/macos/download_modal.png',
  },
  ios: {
    seriesList: '/imgs/v0.0.1-alpha/ios/ios_serielistsearch.webp',
    seriesDetail: '/imgs/v0.0.1-alpha/ios/ios_seriedetail.webp',
    downloadModal: '/imgs/v0.0.1-alpha/ios/ios_seriemodaldownload.webp',
    loadingScreen: '/imgs/v0.0.1-alpha/ios/ios_loadingscreen.webp',
  }
} as const;
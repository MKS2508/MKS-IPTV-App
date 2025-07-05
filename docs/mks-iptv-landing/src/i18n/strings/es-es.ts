/**
 * Strings localizadas en español para la aplicación MKS-IPTV
 * Solo contiene etiquetas específicas de la app, no contenido descriptivo
 */

export const strings = {
  // Navegación principal
  nav: {
    home: 'Inicio',
    installation: 'Instalación', 
    downloads: 'Descargas',
    screenshots: 'Screenshots',
    github: 'GitHub'
  },

  // Botones y acciones
  buttons: {
    downloadNow: 'Descargar Ahora',
    viewScreenshots: 'Ver Screenshots',
    viewInstallation: 'Ver Guía de Instalación',
    download: 'Descargar',
    requestAccess: 'Solicitar Acceso',
    openIssue: 'Abrir Issue',
    viewLicense: 'Ver Licencia Completa',
    downloadForiOS: 'Descargar para iOS',
    downloadFormacOS: 'Descargar para macOS',
    downloadForTvOS: 'Descargar para tvOS',
    installGuide: 'Guía de Instalación'
  },

  // Etiquetas de estado
  status: {
    available: 'Disponible',
    notAvailable: 'No Disponible',
    comingSoon: 'Próximamente',
    recommended: 'Recomendado',
    byInvitation: 'Por invitación',
    native: 'Nativo',
    universal: 'Universal'
  },

  // Metadatos y SEO
  meta: {
    title: 'MKS-IPTV - Tu cliente IPTV multiplataforma',
    description: 'Cliente IPTV nativo para iOS, macOS y tvOS. Streaming en vivo, descargas avanzadas y diseño Liquid Glass.',
    titleHome: 'MKS-IPTV - Tu cliente IPTV multiplataforma',
    titleInstallation: 'Instalación - MKS-IPTV',
    titleDownloads: 'Descargas - MKS-IPTV',
    titleScreenshots: 'Screenshots - MKS-IPTV'
  },

  // Plataformas
  platforms: {
    ios: 'iOS',
    macos: 'macOS', 
    tvos: 'tvOS',
    iphone: 'iPhone',
    ipad: 'iPad',
    mac: 'Mac',
    appleTV: 'Apple TV',
    allPlatforms: 'Todas las Plataformas'
  },

  // Métodos de instalación
  installation: {
    method1: 'Método 1',
    method2: 'Método 2',
    altstore: 'AltStore',
    testflight: 'TestFlight',
    directDownload: 'Descarga Directa',
    requiresXcode: 'Requiere Xcode'
  },

  // Términos técnicos
  technical: {
    version: 'Versión',
    size: 'Tamaño',
    requires: 'Requiere',
    lastUpdate: 'Última actualización',
    systemRequirements: 'Requisitos del Sistema',
    build: 'Build',
    fileFormat: 'Formato'
  },

  // Navegación de filtros y categorías
  filters: {
    all: 'Todos',
    byPlatform: 'Por Plataforma',
    filterBy: 'Filtrar por'
  },

  // Footer
  footer: {
    navigation: 'Navegación',
    resources: 'Recursos',
    downloadApp: 'Descargar App',
    documentation: 'Documentación',
    sourceCode: 'Código Fuente',
    releases: 'Releases',
    issues: 'Issues',
    copyright: 'Licenciado bajo GPL-3.0',
    privacy: 'Privacidad',
    terms: 'Términos',
    license: 'Licencia'
  },

  // Mensajes de error y estados
  messages: {
    comingSoon: 'Próximamente disponible',
    needsHelp: '¿Necesitas ayuda?',
    responseTime: 'Respuesta en 24-48 horas',
    currentlyAvailable: 'Actualmente disponible mediante instalación manual y TestFlight'
  },

  // Accesibilidad
  a11y: {
    openMenu: 'Abrir menú de navegación',
    closeMenu: 'Cerrar menú de navegación',
    mainNavigation: 'Navegación principal',
    mobileNavigation: 'Navegación móvil',
    previousScreenshot: 'Screenshot anterior',
    nextScreenshot: 'Siguiente screenshot',
    screenshot: 'Screenshot'
  },

  // Secciones de la página
  sections: {
    features: 'Características Principales',
    carousel: 'Galería de Imágenes',
    stats: 'Estadísticas'
  },

  // Estadísticas
  stats: {
    platforms: 'Plataformas Soportadas',
    native: 'Nativo Swift',
    opensource: 'Código Abierto'
  }
} as const;

// Tipo para autocompletado y type safety
export type Strings = typeof strings;
export type StringKey = keyof Strings;

// Helper function para acceso a strings anidadas
export function getString(path: string): string {
  const keys = path.split('.');
  let current: any = strings;
  
  for (const key of keys) {
    if (current && typeof current === 'object' && key in current) {
      current = current[key];
    } else {
      console.warn(`String key not found: ${path}`);
      return path; // Fallback al path original
    }
  }
  
  return typeof current === 'string' ? current : path;
}
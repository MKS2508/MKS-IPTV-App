/**
 * Bridge para acceder al contenido de los markdown legacy
 * Este archivo mapea el contenido desde /docs/*.md al nuevo sistema Astro
 */

// Contenido extraído del legacy /docs/index.md
export const homeContent = {
  hero: {
    tagline: "The Ultimate IPTV Experience for Apple Devices",
    version: "v1.0-beta",
    platforms: "iOS • macOS • tvOS",
    swift: "Swift 6.0",
    buttons: {
      exploreFeatures: "Explore Features",
      viewScreenshots: "View Screenshots"
    }
  },
  
  features: [
    {
      icon: "🍎",
      title: "Native Apple Experience", 
      description: "Built with Swift 6 & SwiftUI for optimal performance and seamless integration with the Apple ecosystem."
    },
    {
      icon: "📺",
      title: "Live TV & VOD",
      description: "Stream your favorite live channels, movies, and series with adaptive quality and minimal buffering."
    },
    {
      icon: "📥", 
      title: "Advanced Downloads",
      description: "Download content for offline viewing with real-time progress tracking and queue management."
    },
    {
      icon: "🎨",
      title: "Liquid Glass Design", 
      description: "Experience the cutting-edge UI patterns from iOS 26 with beautiful translucency and fluid animations."
    },
    {
      icon: "💻",
      title: "Multi-platform",
      description: "Works seamlessly across iOS, macOS, and tvOS with platform-specific optimizations."
    },
    {
      icon: "🚀",
      title: "High Performance",
      description: "Optimized streaming with HTTP proxy servers and hardware acceleration for smooth playback."
    }
  ],
  
  carousel: {
    title: "See It in Action",
    subtitle: "Experience the beautiful interface and powerful features",
    slides: [
      {
        image: "imgs/v0.0.1-alpha/macos/listview_liquidglasstopbar.png",
        title: "Liquid Glass Design",
        description: "Modern translucent UI patterns from iOS 26"
      },
      {
        image: "imgs/v0.0.1-alpha/macos/DownloadsSection_1.png", 
        title: "Advanced Downloads",
        description: "Real-time progress tracking and queue management"
      },
      {
        image: "imgs/v0.0.1-alpha/macos/seriesdetail_1.png",
        title: "Rich Content Views", 
        description: "Comprehensive series and episode management"
      },
      {
        image: "imgs/v0.0.1-alpha/macos/download_modal.png",
        title: "Flexible Configuration",
        description: "Customizable download settings and formats"
      }
    ]
  }
};

// Contenido para página de instalación (extraído de installation.md)
export const installationContent = {
  hero: {
    title: "Installation Guide",
    subtitle: "Step-by-step instructions to get you started on all Apple platforms"
  },
  
  methods: {
    ios: [
      {
        title: "AltStore Method",
        recommended: true,
        steps: [
          "Download and install AltStore from altstore.io",
          "Connect your iPhone/iPad to your Mac with AltServer running", 
          "Open the .ipa file with AltStore to install MKS-IPTV"
        ]
      },
      {
        title: "TestFlight",
        invitation: true,
        steps: [
          "Request access to TestFlight beta",
          "Install TestFlight from App Store",
          "Accept the invitation link on your device"
        ]
      }
    ],
    
    macos: {
      title: "macOS Installation",
      steps: [
        "Download the .app.zip file",
        "Extract and drag MKS-IPTV.app to Applications folder",
        "Right-click → Open → Confirm 'Open' in security warning"
      ],
      note: "macOS will show a warning about 'unidentified developer'. This is normal for apps distributed outside the Mac App Store."
    },
    
    tvos: {
      title: "tvOS Installation", 
      requirements: "Requires Xcode 16 Beta and developer account",
      steps: [
        "Connect your Apple TV to Mac via USB-C",
        "Open the project in Xcode",
        "Run the app on your Apple TV"
      ]
    }
  }
};

// Contenido para página de descargas
export const downloadContent = {
  hero: {
    title: "Downloads",
    subtitle: "Get the latest builds for all platforms",
    version: "v0.0.1-alpha",
    lastUpdate: "January 2025"
  },
  
  platforms: {
    ios: {
      title: "iOS (iPhone & iPad)",
      directDownload: {
        title: "Direct Download (.ipa)",
        recommended: true,
        version: "v0.0.1-alpha",
        size: "~45 MB", 
        requires: "iOS 17+",
        note: "Requires AltStore or TestFlight"
      },
      testflight: {
        title: "TestFlight (Beta)",
        invitation: true,
        features: [
          "Easier installation",
          "Automatic updates", 
          "Limited access",
          "90 days duration"
        ]
      }
    },
    
    macos: {
      title: "macOS (Intel & Apple Silicon)",
      universal: {
        title: "Universal Application",
        version: "v0.0.1-alpha",
        size: "~85 MB",
        requires: "macOS 14+",
        features: [
          "Intel & Apple Silicon",
          "TouchBar support",
          "Liquid Glass UI"
        ]
      }
    }
  },
  
  systemRequirements: {
    ios: [
      "iOS 17.0 or later",
      "iPhone 12 or later", 
      "iPad (9th gen) or later",
      "1 GB free space",
      "Internet connection"
    ],
    macos: [
      "macOS 14.0 or later",
      "Intel or Apple Silicon",
      "8 GB RAM minimum", 
      "2 GB free space",
      "OpenGL 4.1+ support"
    ],
    tvos: [
      "tvOS 17.0 or later",
      "Apple TV 4K (2nd gen+)",
      "Apple TV HD compatible",
      "Xcode for installation",
      "Developer account"
    ]
  }
};

// Helper function para obtener contenido específico
export function getContent(section: 'home' | 'installation' | 'download') {
  switch (section) {
    case 'home':
      return homeContent;
    case 'installation': 
      return installationContent;
    case 'download':
      return downloadContent;
    default:
      return null;
  }
}
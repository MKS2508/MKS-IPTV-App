//
//  PlatformAdaptiveLayout.swift
//  mks-multiplatform-iptv
//
//  Platform-adaptive layout utilities following Apple's Human Interface Guidelines
//  Target: iOS 26+, macOS 26+
//

import SwiftUI
import IPTVCore

// MARK: - Platform Detection

/// Platform-aware layout traits
enum PlatformLayoutTraits {
    /// Current platform
    static var currentPlatform: Platform {
        #if os(macOS)
        return .macOS
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #elseif os(tvOS)
        return .tvOS
        #endif
    }

    /// Whether the current platform supports sidebar navigation
    static var supportsSidebar: Bool {
        switch currentPlatform {
        case .macOS, .iPad:
            return true
        case .iPhone, .tvOS:
            return false
        }
    }

    /// Whether the current platform uses compact tabs
    static var usesCompactTabs: Bool {
        currentPlatform == .iPhone
    }
}

/// Supported platforms
enum Platform {
    case macOS
    case iPad
    case iPhone
    case tvOS

    /// Minimum sidebar width for this platform
    var minSidebarWidth: CGFloat {
        switch self {
        case .macOS: return 200
        case .iPad: return 250
        case .iPhone: return 0 // No sidebar
        case .tvOS: return 300
        }
    }

    /// Ideal sidebar width for this platform
    var idealSidebarWidth: CGFloat {
        switch self {
        case .macOS: return 250
        case .iPad: return 300
        case .iPhone: return 0
        case .tvOS: return 350
        }
    }

    /// Maximum sidebar width for this platform
    var maxSidebarWidth: CGFloat {
        switch self {
        case .macOS: return 300
        case .iPad: return 350
        case .iPhone: return 0
        case .tvOS: return 400
        }
    }
}

// MARK: - Adaptive Padding

/// Platform-adaptive padding values
enum AdaptivePadding {
    /// Standard content padding
    static func standard(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> CGFloat {
        switch platform {
        case .macOS: return 16
        case .iPad: return 20
        case .iPhone: return 16
        case .tvOS: return 40
        }
    }

    /// Compact padding for dense layouts
    static func compact(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> CGFloat {
        switch platform {
        case .macOS: return 8
        case .iPad: return 12
        case .iPhone: return 8
        case .tvOS: return 20
        }
    }

    /// Section spacing
    static func section(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> CGFloat {
        switch platform {
        case .macOS: return 12
        case .iPad: return 16
        case .iPhone: return 12
        case .tvOS: return 24
        }
    }
}

// MARK: - Adaptive Typography

/// Platform-adaptive font styles
enum AdaptiveTypography {
    /// Large title - platform adjusted
    static func largeTitle(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> Font {
        switch platform {
        case .macOS: return .system(size: 28, weight: .bold)
        case .iPad: return .system(size: 34, weight: .bold)
        case .iPhone: return .system(size: 28, weight: .bold)
        case .tvOS: return .system(size: 48, weight: .bold)
        }
    }

    /// Title - platform adjusted
    static func title(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> Font {
        switch platform {
        case .macOS: return .system(size: 22, weight: .semibold)
        case .iPad: return .system(size: 28, weight: .semibold)
        case .iPhone: return .system(size: 22, weight: .semibold)
        case .tvOS: return .system(size: 38, weight: .semibold)
        }
    }

    /// Headline - platform adjusted
    static func headline(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> Font {
        switch platform {
        case .macOS: return .system(size: 14, weight: .semibold)
        case .iPad: return .system(size: 17, weight: .semibold)
        case .iPhone: return .system(size: 15, weight: .semibold)
        case .tvOS: return .system(size: 24, weight: .semibold)
        }
    }

    /// Body - platform adjusted
    static func body(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> Font {
        switch platform {
        case .macOS: return .system(size: 13)
        case .iPad: return .system(size: 17)
        case .iPhone: return .system(size: 15)
        case .tvOS: return .system(size: 22)
        }
    }

    /// Caption - platform adjusted
    static func caption(for platform: Platform = PlatformLayoutTraits.currentPlatform) -> Font {
        switch platform {
        case .macOS: return .system(size: 11)
        case .iPad: return .system(size: 14)
        case .iPhone: return .system(size: 12)
        case .tvOS: return .system(size: 18)
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply platform-adaptive standard padding
    func adaptivePadding() -> some View {
        self.padding(AdaptivePadding.standard())
    }

    /// Apply platform-adaptive compact padding
    func adaptiveCompactPadding() -> some View {
        self.padding(AdaptivePadding.compact())
    }

    /// Apply platform-adaptive section spacing
    func adaptiveSectionSpacing() -> some View {
        self.padding(.vertical, AdaptivePadding.section())
    }

    /// Conditional view modifier based on platform
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Platform-specific view modifier
    @ViewBuilder
    func platformModifier<macOSContent: View, iOSContent: View>(
        macOS: (Self) -> macOSContent,
        iOS: (Self) -> iOSContent
    ) -> some View {
        #if os(macOS)
        macOS(self)
        #else
        iOS(self)
        #endif
    }
}


//
//  LayoutIndex.swift
//  mks-multiplatform-iptv
//
//  Barrel export for all layout utilities
//  Target: iOS 26+, macOS 26+
//

import SwiftUI

// MARK: - Layout System API

/// Platform-adaptive layout system
enum LayoutSystem {
    /// Current platform
    static var currentPlatform: Platform {
        PlatformLayoutTraits.currentPlatform
    }

    /// Whether sidebar navigation is supported
    static var supportsSidebar: Bool {
        PlatformLayoutTraits.supportsSidebar
    }

    /// Get adaptive padding for current platform
    static func padding(standard: Bool = true) -> CGFloat {
        standard ? AdaptivePadding.standard() : AdaptivePadding.compact()
    }

    /// Get adaptive grid configuration
    static func gridConfiguration() -> AdaptiveGridConfiguration {
        .current(horizontalSizeClass: nil, verticalSizeClass: nil)
    }
}

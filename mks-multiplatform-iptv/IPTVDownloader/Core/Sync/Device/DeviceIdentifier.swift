//
//  DeviceIdentifier.swift
//  mks-multiplatform-iptv
//
//  Cross-platform device identification utility.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Provides stable, cross-platform device metadata for CloudKit device tracking.
///
/// Uses platform-appropriate APIs to gather the device name, OS version, model
/// identifier, and a persistent UUID that survives app reinstalls (stored in
/// `UserDefaults`). SF Symbol names are resolved based on the device idiom.
enum DeviceIdentifier {

    /// User-facing device name (e.g. "iPhone de Mario", "MacBook Pro").
    static var deviceName: String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown"
        #endif
    }

    /// Platform string: `"iOS"`, `"tvOS"`, or `"macOS"`.
    static var platform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }

    /// OS version string (e.g. "26.0").
    static var osVersion: String {
        let info = ProcessInfo.processInfo.operatingSystemVersion
        return "\(info.majorVersion).\(info.minorVersion)"
    }

    /// Hardware model identifier from `utsname` (e.g. "iPhone17,1", "Mac15,6").
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
    }

    /// Persistent UUID for this device, generated once and stored in `UserDefaults`.
    ///
    /// Survives app updates but not a full reinstall + UserDefaults wipe.
    static var deviceUUID: UUID {
        let key = "com.mks.iptv.deviceUUID"
        if let stored = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }

    /// SF Symbol name appropriate for this device type.
    static var deviceSymbol: String {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "iphone"
        case .pad: return "ipad"
        default: return "iphone"
        }
        #elseif os(tvOS)
        return "appletv"
        #elseif os(macOS)
        return "laptopcomputer"
        #else
        return "desktopcomputer"
        #endif
    }

    /// App version string from the main bundle (e.g. "2.5.0").
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

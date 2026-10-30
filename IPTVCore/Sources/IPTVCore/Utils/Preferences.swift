//
//  Preferences.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 17/11/24.
//

import Foundation

/// App-level UserDefaults keys for download and debug preferences.
///
/// > Note: Log-related keys (`MKSLog.level.*`, `MKSLog.directory`) are managed
/// > exclusively by ``MKSLogConfig`` and should not be accessed directly here.
extension UserDefaults {
    private static let downloadPathKey = "DownloadPath"
    private static let showPlayerDebugOverlayKey = "showPlayerDebugOverlay"
    private static let maxConcurrentDownloadsKey = "MaxConcurrentDownloads"

    public static var downloadPath: String {
        get {
            // Intentar obtener el valor almacenado en UserDefaults
            if let storedPath = UserDefaults.standard.string(forKey: downloadPathKey) {
                return storedPath
            }
            // macOS: ~/Downloads, iOS: app Documents directory
            #if os(macOS)
            let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            #else
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            #endif
            return directory.path
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: downloadPathKey)
        }
    }

    /// Maximum number of downloads running at once (1–3). Additional downloads
    /// wait in the queue and start automatically as slots free up.
    public static var maxConcurrentDownloads: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: maxConcurrentDownloadsKey)
            return stored == 0 ? 1 : min(max(stored, 1), 3)
        }
        set {
            UserDefaults.standard.setValue(min(max(newValue, 1), 3), forKey: maxConcurrentDownloadsKey)
        }
    }

    /// Whether to show the player debug overlay with live AVPlayer metrics.
    /// Only available in DEBUG builds. Toggled via triple-tap on the player surface
    /// or via Settings.
    public static var showPlayerDebugOverlay: Bool {
        get { UserDefaults.standard.bool(forKey: showPlayerDebugOverlayKey) }
        set { UserDefaults.standard.setValue(newValue, forKey: showPlayerDebugOverlayKey) }
    }
}

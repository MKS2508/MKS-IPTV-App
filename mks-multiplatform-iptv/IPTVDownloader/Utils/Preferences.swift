//
//  Preferences.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 17/11/24.
//

import Foundation

extension UserDefaults {
    private static let downloadPathKey = "DownloadPath"
    private static let showPlayerDebugOverlayKey = "showPlayerDebugOverlay"

    static var downloadPath: String {
        get {
            // Intentar obtener el valor almacenado en UserDefaults
            if let storedPath = UserDefaults.standard.string(forKey: downloadPathKey) {
                return storedPath
            }
            // Si no existe, devolver la carpeta de descargas por defecto
            let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            return downloadsDirectory.path
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: downloadPathKey)
        }
    }

    /// Whether to show the player debug overlay with live AVPlayer metrics.
    /// Only available in DEBUG builds. Toggled via triple-tap on the player surface
    /// or via Settings.
    static var showPlayerDebugOverlay: Bool {
        get { UserDefaults.standard.bool(forKey: showPlayerDebugOverlayKey) }
        set { UserDefaults.standard.setValue(newValue, forKey: showPlayerDebugOverlayKey) }
    }
}

//
//  Preferences.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 17/11/24.
//

import Foundation

extension UserDefaults {
    private static let downloadPathKey = "DownloadPath"

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
}

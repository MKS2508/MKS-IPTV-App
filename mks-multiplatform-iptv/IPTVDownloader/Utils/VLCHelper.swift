import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct VLCHelper {
    
    static func isVLCInstalled() -> Bool {
        #if os(macOS)
        // Check if VLC is installed on macOS
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") {
            return FileManager.default.fileExists(atPath: url.path)
        }
        // Also check common installation paths
        let commonPaths = [
            "/Applications/VLC.app",
            "~/Applications/VLC.app"
        ]
        for path in commonPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return true
            }
        }
        return false
        #else
        // Check if VLC is installed on iOS
        return UIApplication.shared.canOpenURL(URL(string: "vlc://")!)
        #endif
    }
    
    static func openInVLC(url: String) {
        #if os(macOS)
        // Open in VLC on macOS
        if let vlcURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [url]
            
            NSWorkspace.shared.open([URL(string: url)!], 
                                  withApplicationAt: vlcURL,
                                  configuration: configuration) { _, error in
                if let error = error {
                    MKSLog.app.error("Error opening VLC: \(error)")
                }
            }
        } else {
            // Try using open command as fallback
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "VLC", url]
            
            do {
                try task.run()
            } catch {
                MKSLog.app.error("Failed to open VLC: \(error)")
            }
        }
        #else
        // Open in VLC on iOS
        if let vlcURL = URL(string: "vlc://x-callback-url/stream?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)") {
            UIApplication.shared.open(vlcURL)
        }
        #endif
    }
}
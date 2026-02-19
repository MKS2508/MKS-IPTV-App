import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Shared Download Utilities
// Consolidates duplicated functions from multiple download view files

/// Extracts the year from a date string in "yyyy-MM-dd" format
/// - Parameter dateString: Date string in "yyyy-MM-dd" format
/// - Returns: Year as string, or original string if parsing fails
public func extractYear(from dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    if let date = formatter.date(from: dateString) {
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        return yearFormatter.string(from: date)
    }

    return dateString
}

/// Opens a folder selection dialog (macOS only)
/// - Parameter completion: Callback with selected URL or nil if cancelled
public func selectFolder(completion: @escaping (URL?) -> Void) {
    #if os(macOS)
    DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"

        panel.begin { result in
            if result == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }
    #else
    print("Folder selection is not supported on iOS.")
    completion(nil)
    #endif
}

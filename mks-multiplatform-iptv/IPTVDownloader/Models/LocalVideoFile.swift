import Foundation
import UniformTypeIdentifiers

/// Represents a local video file added by the user to My Content.
struct LocalVideoFile: Identifiable, Hashable, Codable {
    let id: UUID
    let url: URL
    let displayName: String
    let fileSize: Int64?
    let addedDate: Date
    let fileExtension: String
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.displayName = url.deletingPathExtension().lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.addedDate = Date()
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            self.fileSize = size
        } else {
            self.fileSize = nil
        }
    }
    
    var formattedSize: String {
        guard let size = fileSize else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var fileTypeIcon: String {
        switch fileExtension {
        case "mkv": return "video.fill"
        case "mp4", "m4v": return "play.rectangle.fill"
        case "avi": return "film"
        case "mov": return "play.circle.fill"
        case "wmv", "asf": return "windows.logo"
        case "flv", "f4v": return "bolt.fill"
        case "webm": return "globe"
        case "ts", "m2ts", "mts": return "antenna.radiowaves.left.and.right"
        default: return "doc.video.fill"
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LocalVideoFile, rhs: LocalVideoFile) -> Bool {
        lhs.id == rhs.id
    }
}

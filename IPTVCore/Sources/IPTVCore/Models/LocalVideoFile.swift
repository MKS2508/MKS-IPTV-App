import Foundation
import UniformTypeIdentifiers

/// Represents a local video file added by the user to My Content.
public struct LocalVideoFile: Identifiable, Hashable, Codable {
    public let id: UUID
    public let url: URL
    public let displayName: String
    public let fileSize: Int64?
    public let addedDate: Date
    public let fileExtension: String
    
    public init(url: URL) {
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
    
    public var formattedSize: String {
        guard let size = fileSize else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    public var fileTypeIcon: String {
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
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: LocalVideoFile, rhs: LocalVideoFile) -> Bool {
        lhs.id == rhs.id
    }
}

import Foundation
import IPTVCore

// MARK: - Local File Metadata

/// Editable metadata for a local file. Stored separately so we can update displayName after metadata enrichment.
struct LocalFileMetadata: Codable {
    var displayName: String
    var customTitle: String?
}

// MARK: - Local File Manager

/// Persists the user's locally-imported video files across app sessions.
/// Thread-safe: all operations are nonisolated (pure file I/O + JSON).
final class LocalFileManager: @unchecked Sendable {
    static let shared = LocalFileManager()

    private let filesFileName = "mks-iptv-local-files.json"
    private let metaFileName = "mks-iptv-local-files-meta.json"

    private var cacheURL: URL {
        let base: URL
        #if os(tvOS)
        base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        #else
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #endif
        return base.appendingPathComponent("MKS-IPTV", isDirectory: true)
    }

    private var filesURL: URL { cacheURL.appendingPathComponent(filesFileName) }
    private var metaURL: URL { cacheURL.appendingPathComponent(metaFileName) }

    private let queue = DispatchQueue(label: "LocalFileManager", attributes: .concurrent)

    init() {}

    // MARK: - Load

    /// Loads persisted files, filtering out files that no longer exist on disk.
    func load() -> (files: [LocalVideoFile], metadata: [UUID: LocalFileMetadata]) {
        let files = loadFiles().filter { FileManager.default.fileExists(atPath: $0.url.path) }
        let meta = loadMetadata()
        return (files, meta)
    }

    private func loadFiles() -> [LocalVideoFile] {
        guard FileManager.default.fileExists(atPath: filesURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: filesURL)
            return try JSONDecoder().decode([LocalVideoFile].self, from: data)
        } catch {
            MKSLog.media.error("[LocalFileManager] Failed to load files: \(error)")
            return []
        }
    }

    private func loadMetadata() -> [UUID: LocalFileMetadata] {
        guard FileManager.default.fileExists(atPath: metaURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: metaURL)
            return try JSONDecoder().decode([UUID: LocalFileMetadata].self, from: data)
        } catch {
            MKSLog.media.error("[LocalFileManager] Failed to load metadata: \(error)")
            return [:]
        }
    }

    // MARK: - Save (all at once)

    /// Persist files and metadata. Called after any mutation.
    func save(_ files: [LocalVideoFile], _ metadata: [UUID: LocalFileMetadata]) {
        do {
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            let filesData = try JSONEncoder().encode(files)
            try filesData.write(to: filesURL, options: .atomic)
            let metaData = try JSONEncoder().encode(metadata)
            try metaData.write(to: metaURL, options: .atomic)
        } catch {
            MKSLog.media.error("[LocalFileManager] Save failed: \(error)")
        }
    }

    // MARK: - Add

    /// Add a file, returns new arrays (caller applies them).
    func add(_ file: LocalVideoFile, to files: [LocalVideoFile], metadata: [UUID: LocalFileMetadata]) -> [LocalVideoFile] {
        guard !files.contains(where: { $0.url == file.url }) else { return files }
        var new = files
        new.append(file)
        var newMeta = metadata
        newMeta[file.id] = LocalFileMetadata(displayName: file.displayName)
        save(new, newMeta)
        return new
    }

    // MARK: - Remove

    /// Remove a file by ID, returns new arrays. Does NOT delete the file from disk.
    func remove(id: UUID, from files: [LocalVideoFile], metadata: [UUID: LocalFileMetadata]) -> [LocalVideoFile] {
        var newFiles = files
        newFiles.removeAll { $0.id == id }
        var newMeta = metadata
        newMeta.removeValue(forKey: id)
        save(newFiles, newMeta)
        return newFiles
    }

    // MARK: - Update display name

    func updateDisplayName(id: UUID, displayName: String, files: [LocalVideoFile], metadata: [UUID: LocalFileMetadata]) -> [UUID: LocalFileMetadata] {
        var newMeta = metadata
        newMeta[id]?.displayName = displayName
        save(files, newMeta)
        return newMeta
    }
}

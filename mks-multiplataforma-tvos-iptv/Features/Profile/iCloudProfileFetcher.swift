//
//  iCloudProfileFetcher.swift
//  mks-multiplataforma-tvos-iptv
//
//  Read-only CloudKit pull of IPTVProfile records. Mirrors the schema used
//  by the iOS/macOS ProfileSyncManager so a profile saved on iPhone shows
//  up automatically on Apple TV without manual entry.
//
//  Schema (must stay in sync with mks-multiplatform-iptv/.../CloudKitContainer.swift
//  + CloudKitRecordTypes.swift):
//    container: iCloud.com.mks.iptv
//    zone     : IPTVProfilesZone
//    record   : IPTVProfile
//    fields   : name (String), baseURL (String), username (String),
//               password (String), fileExtension (String), lastModified (Date)
//

import Foundation
import CloudKit
import IPTVCore

@MainActor
final class iCloudProfileFetcher: ObservableObject {
    enum State: Equatable {
        case idle
        case fetching
        case found([IPTVProfile])
        case empty
        case notSignedIn
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.fetching, .fetching),
                 (.empty, .empty), (.notSignedIn, .notSignedIn):
                return true
            case (.found(let a), .found(let b)):
                return a.map(\.id) == b.map(\.id)
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle

    private let containerIdentifier = "iCloud.com.mks.iptv"
    private let zoneName = "IPTVProfilesZone"
    private let recordType = "IPTVProfile"

    /// Fields used by the iOS/macOS sync. Must match exactly.
    private enum Field {
        static let name = "name"
        static let baseURL = "baseURL"
        static let username = "username"
        static let password = "password"
        static let fileExtension = "fileExtension"
        static let lastModified = "lastModified"
    }

    func fetch() async {
        state = .fetching
        let container = CKContainer(identifier: containerIdentifier)

        // 1. Account status
        let accountStatus: CKAccountStatus
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            MKSLog.app.error("iCloud accountStatus failed: \(error)")
            state = .notSignedIn
            return
        }

        guard accountStatus == .available else {
            MKSLog.app.warning("iCloud not available: \(String(describing: accountStatus))")
            state = .notSignedIn
            return
        }

        // 2. Fetch all records in the custom zone
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let database = container.privateCloudDatabase

        do {
            let profiles = try await fetchAllRecords(database: database, zoneID: zoneID)
            MKSLog.app.info("iCloud fetch found \(profiles.count) profile(s)")
            state = profiles.isEmpty ? .empty : .found(profiles)
        } catch let error as CKError where error.code == .zoneNotFound {
            MKSLog.app.info("iCloud zone IPTVProfilesZone not found — assuming empty")
            state = .empty
        } catch {
            MKSLog.app.error("iCloud fetch failed: \(error)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Use `CKFetchRecordZoneChangesOperation` with no change token to pull
    /// every record in the zone. Avoids needing a queryable index on the field.
    private func fetchAllRecords(
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [IPTVProfile] {
        try await withCheckedThrowingContinuation { continuation in
            var collected: [CKRecord] = []
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            operation.fetchAllChanges = true
            operation.qualityOfService = .userInitiated

            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result, record.recordType == "IPTVProfile" {
                    collected.append(record)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    let profiles = collected.compactMap { Self.profile(from: $0) }
                    continuation.resume(returning: profiles)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    /// Decode a CKRecord into an IPTVProfile using the shared schema.
    private static func profile(from record: CKRecord) -> IPTVProfile? {
        guard
            let name = record[Field.name] as? String,
            let baseURL = record[Field.baseURL] as? String,
            let username = record[Field.username] as? String,
            let password = record[Field.password] as? String
        else { return nil }

        let fileExtension = record[Field.fileExtension] as? String ?? "mkv"
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()

        return IPTVProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            username: username,
            password: password,
            fileExtension: fileExtension
        )
    }
}

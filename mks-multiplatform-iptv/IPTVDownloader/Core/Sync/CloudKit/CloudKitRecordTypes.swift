//
//  CloudKitRecordTypes.swift
//  mks-multiplatform-iptv
//
//  CKRecord type constants and field name mappings for IPTV models.
//

import Foundation
import CloudKit

/// CloudKit record type constants and field mappings.
///
/// Centralizes all record type names and field keys used in CloudKit
/// to avoid string duplication across the codebase.
enum CloudKitRecordTypes {
    /// Record type for IPTV profiles.
    static let profile = "IPTVProfile"

    /// Record type for synced devices.
    static let syncedDevice = "SyncedDevice"

    /// Field names for the IPTVProfile record type.
    enum ProfileFields {
        static let name = "name"
        static let baseURL = "baseURL"
        static let username = "username"
        static let password = "password"
        static let fileExtension = "fileExtension"
        static let lastModified = "lastModified"
    }

    /// Field names for the SyncedDevice record type.
    enum DeviceFields {
        static let deviceName = "deviceName"
        static let modelIdentifier = "modelIdentifier"
        static let platform = "platform"
        static let osVersion = "osVersion"
        static let appVersion = "appVersion"
        static let lastActiveDate = "lastActiveDate"
        static let lastModified = "lastModified"
        static let deviceSymbol = "deviceSymbol"
    }
}

// MARK: - IPTVProfile + Syncable

extension IPTVProfile: Syncable {
    static var recordType: String { CloudKitRecordTypes.profile }

    /// The local modification date, stored alongside the profile.
    /// Falls back to `.distantPast` if not tracked.
    var lastModifiedDate: Date {
        UserDefaults.standard.object(
            forKey: "profile_modified_\(id.uuidString)"
        ) as? Date ?? .distantPast
    }

    /// Persists the modification timestamp for this profile.
    func touchModifiedDate() {
        UserDefaults.standard.set(Date(), forKey: "profile_modified_\(id.uuidString)")
    }

    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[CloudKitRecordTypes.ProfileFields.name] = name as CKRecordValue
        record[CloudKitRecordTypes.ProfileFields.baseURL] = baseURL as CKRecordValue
        record[CloudKitRecordTypes.ProfileFields.username] = username as CKRecordValue
        record[CloudKitRecordTypes.ProfileFields.password] = password as CKRecordValue
        record[CloudKitRecordTypes.ProfileFields.fileExtension] = fileExtension as CKRecordValue
        record[CloudKitRecordTypes.ProfileFields.lastModified] = lastModifiedDate as CKRecordValue
        return record
    }

    static func fromRecord(_ record: CKRecord) -> IPTVProfile? {
        guard record.recordType == recordType,
              let name = record[CloudKitRecordTypes.ProfileFields.name] as? String,
              let baseURL = record[CloudKitRecordTypes.ProfileFields.baseURL] as? String,
              let username = record[CloudKitRecordTypes.ProfileFields.username] as? String,
              let password = record[CloudKitRecordTypes.ProfileFields.password] as? String
        else {
            return nil
        }

        let fileExtension = record[CloudKitRecordTypes.ProfileFields.fileExtension] as? String ?? "mkv"
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()

        let profile = IPTVProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            username: username,
            password: password,
            fileExtension: fileExtension
        )

        // Persist the remote modification date locally
        if let remoteDate = record[CloudKitRecordTypes.ProfileFields.lastModified] as? Date {
            UserDefaults.standard.set(remoteDate, forKey: "profile_modified_\(id.uuidString)")
        }

        return profile
    }
}

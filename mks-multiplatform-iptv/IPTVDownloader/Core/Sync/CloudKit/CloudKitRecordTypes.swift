//
//  CloudKitRecordTypes.swift
//  mks-multiplatform-iptv
//
//  CKRecord type constants and field name mappings for IPTV models.
//

import Foundation
import CloudKit
import IPTVCore

/// CloudKit record type constants and field mappings.
///
/// Centralizes all record type names and field keys used in CloudKit
/// to avoid string duplication across the codebase.
enum CloudKitRecordTypes {
    /// Record type for IPTV profiles.
    static let profile = "IPTVProfile"

    /// Record type for synced devices.
    static let syncedDevice = "SyncedDevice"

    /// Record type for VOD watch history (movies + episodes).
    static let watchHistoryEntry = "WatchHistoryEntry"

    /// Record type for recently watched live channels.
    static let recentChannelEntry = "RecentChannelEntry"

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

    /// Field names for the WatchHistoryEntry record type.
    enum WatchHistoryFields {
        static let profileId = "profileId"
        static let contentType = "contentType"
        static let contentId = "contentId"
        static let lastPosition = "lastPosition"
        static let totalDuration = "totalDuration"
        static let progress = "progress"
        static let isCompleted = "isCompleted"
        static let displayTitle = "displayTitle"
        static let posterURL = "posterURL"
        static let backdropURL = "backdropURL"
        static let seriesId = "seriesId"
        static let showTitle = "showTitle"
        static let seasonNumber = "seasonNumber"
        static let episodeNumber = "episodeNumber"
        static let episodeTitle = "episodeTitle"
        static let containerExtension = "containerExtension"
        static let createdAt = "createdAt"
        static let lastWatchedAt = "lastWatchedAt"
        static let lastModifiedDate = "lastModifiedDate"
    }

    /// Field names for the RecentChannelEntry record type.
    enum RecentChannelFields {
        static let profileId = "profileId"
        static let channelStreamId = "channelStreamId"
        static let channelName = "channelName"
        static let channelIcon = "channelIcon"
        static let categoryId = "categoryId"
        static let watchCount = "watchCount"
        static let lastWatchedAt = "lastWatchedAt"
    }
}

// MARK: - WatchHistoryEntry CKRecord helpers

extension WatchHistoryEntry {
    /// Stable record name: profileId + contentType + contentId.
    /// Same content on every device maps to the same CKRecord.
    var ckRecordName: String {
        "\(profileId.uuidString)_\(contentType)_\(contentId)"
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let f = CloudKitRecordTypes.WatchHistoryFields.self
        let recordID = CKRecord.ID(recordName: ckRecordName, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordTypes.watchHistoryEntry, recordID: recordID)
        record[f.profileId] = profileId.uuidString as CKRecordValue
        record[f.contentType] = contentType as CKRecordValue
        record[f.contentId] = contentId as CKRecordValue
        record[f.lastPosition] = lastPosition as CKRecordValue
        record[f.totalDuration] = totalDuration as CKRecordValue
        record[f.progress] = progress as CKRecordValue
        record[f.isCompleted] = (isCompleted ? 1 : 0) as CKRecordValue
        record[f.displayTitle] = displayTitle as CKRecordValue
        if let v = posterURL        { record[f.posterURL] = v as CKRecordValue }
        if let v = backdropURL      { record[f.backdropURL] = v as CKRecordValue }
        if let v = seriesId         { record[f.seriesId] = v as CKRecordValue }
        if let v = showTitle        { record[f.showTitle] = v as CKRecordValue }
        if let v = seasonNumber     { record[f.seasonNumber] = v as CKRecordValue }
        if let v = episodeNumber    { record[f.episodeNumber] = v as CKRecordValue }
        if let v = episodeTitle     { record[f.episodeTitle] = v as CKRecordValue }
        if let v = containerExtension { record[f.containerExtension] = v as CKRecordValue }
        record[f.createdAt] = createdAt as CKRecordValue
        record[f.lastWatchedAt] = lastWatchedAt as CKRecordValue
        record[f.lastModifiedDate] = lastModifiedDate as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> (profileId: UUID, contentType: String, contentId: String, entry: WatchHistoryEntry)? {
        let f = CloudKitRecordTypes.WatchHistoryFields.self
        guard
            let profileIdStr = record[f.profileId] as? String,
            let profileId = UUID(uuidString: profileIdStr),
            let contentType = record[f.contentType] as? String,
            let contentId = record[f.contentId] as? String,
            let displayTitle = record[f.displayTitle] as? String
        else { return nil }

        let entry = WatchHistoryEntry(
            profileId: profileId,
            contentType: contentType,
            contentId: contentId,
            lastPosition: record[f.lastPosition] as? Double ?? 0,
            totalDuration: record[f.totalDuration] as? Double ?? 0,
            progress: record[f.progress] as? Double ?? 0,
            isCompleted: (record[f.isCompleted] as? Int ?? 0) != 0,
            displayTitle: displayTitle,
            posterURL: record[f.posterURL] as? String,
            backdropURL: record[f.backdropURL] as? String,
            seriesId: record[f.seriesId] as? Int,
            showTitle: record[f.showTitle] as? String,
            seasonNumber: record[f.seasonNumber] as? Int,
            episodeNumber: record[f.episodeNumber] as? Int,
            episodeTitle: record[f.episodeTitle] as? String,
            containerExtension: record[f.containerExtension] as? String
        )
        if let v = record[f.createdAt] as? Date        { entry.createdAt = v }
        if let v = record[f.lastWatchedAt] as? Date    { entry.lastWatchedAt = v }
        if let v = record[f.lastModifiedDate] as? Date { entry.lastModifiedDate = v }
        return (profileId, contentType, contentId, entry)
    }
}

// MARK: - RecentChannelEntry CKRecord helpers

extension RecentChannelEntry {
    var ckRecordName: String {
        "\(profileId.uuidString)_channel_\(channelStreamId)"
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let f = CloudKitRecordTypes.RecentChannelFields.self
        let recordID = CKRecord.ID(recordName: ckRecordName, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitRecordTypes.recentChannelEntry, recordID: recordID)
        record[f.profileId] = profileId.uuidString as CKRecordValue
        record[f.channelStreamId] = channelStreamId as CKRecordValue
        record[f.channelName] = channelName as CKRecordValue
        if let v = channelIcon { record[f.channelIcon] = v as CKRecordValue }
        if let v = categoryId  { record[f.categoryId] = v as CKRecordValue }
        record[f.watchCount] = watchCount as CKRecordValue
        record[f.lastWatchedAt] = lastWatchedAt as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> (profileId: UUID, channelStreamId: Int, entry: RecentChannelEntry)? {
        let f = CloudKitRecordTypes.RecentChannelFields.self
        guard
            let profileIdStr = record[f.profileId] as? String,
            let profileId = UUID(uuidString: profileIdStr),
            let channelStreamId = record[f.channelStreamId] as? Int,
            let channelName = record[f.channelName] as? String
        else { return nil }

        let entry = RecentChannelEntry(
            profileId: profileId,
            channelStreamId: channelStreamId,
            channelName: channelName,
            channelIcon: record[f.channelIcon] as? String,
            categoryId: record[f.categoryId] as? String
        )
        if let v = record[f.watchCount] as? Int         { entry.watchCount = v }
        if let v = record[f.lastWatchedAt] as? Date     { entry.lastWatchedAt = v }
        return (profileId, channelStreamId, entry)
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

//
//  SyncedDevice.swift
//  mks-multiplatform-iptv
//
//  Model representing a synced device in CloudKit.
//

import Foundation
import CloudKit
import IPTVCore

/// A device registered in CloudKit for cross-device tracking.
///
/// Each device running the app registers itself as a `SyncedDevice` CKRecord
/// on launch. The Settings screen queries all records to show which devices
/// share the same iCloud account and their last-active timestamps.
struct SyncedDevice: Identifiable, Codable, Sendable {
    /// Persistent device UUID (matches `DeviceIdentifier.deviceUUID`).
    let id: UUID

    /// User-facing device name (e.g. "iPhone de Mario").
    var deviceName: String

    /// Hardware model identifier (e.g. "iPhone17,1").
    var modelIdentifier: String

    /// Platform string: `"iOS"`, `"tvOS"`, or `"macOS"`.
    var platform: String

    /// OS version string (e.g. "26.0").
    var osVersion: String

    /// App version string (e.g. "2.5.0").
    var appVersion: String

    /// Timestamp of the most recent app launch on this device.
    var lastActiveDate: Date

    /// For conflict resolution (last-modified-wins).
    var lastModifiedDate: Date

    /// SF Symbol name for this device type.
    var deviceSymbol: String

    /// Creates a `SyncedDevice` snapshot of the current device.
    static func current() -> SyncedDevice {
        let now = Date()
        return SyncedDevice(
            id: DeviceIdentifier.deviceUUID,
            deviceName: DeviceIdentifier.deviceName,
            modelIdentifier: DeviceIdentifier.modelIdentifier,
            platform: DeviceIdentifier.platform,
            osVersion: DeviceIdentifier.osVersion,
            appVersion: DeviceIdentifier.appVersion,
            lastActiveDate: now,
            lastModifiedDate: now,
            deviceSymbol: DeviceIdentifier.deviceSymbol
        )
    }
}

// MARK: - Syncable Conformance

extension SyncedDevice: Syncable {
    static var recordType: String { CloudKitRecordTypes.syncedDevice }

    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[CloudKitRecordTypes.DeviceFields.deviceName] = deviceName as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.modelIdentifier] = modelIdentifier as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.platform] = platform as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.osVersion] = osVersion as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.appVersion] = appVersion as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.lastActiveDate] = lastActiveDate as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.lastModified] = lastModifiedDate as CKRecordValue
        record[CloudKitRecordTypes.DeviceFields.deviceSymbol] = deviceSymbol as CKRecordValue
        return record
    }

    static func fromRecord(_ record: CKRecord) -> SyncedDevice? {
        guard record.recordType == recordType,
              let deviceName = record[DeviceFields.deviceName] as? String,
              let platform = record[DeviceFields.platform] as? String
        else {
            return nil
        }

        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let modelIdentifier = record[DeviceFields.modelIdentifier] as? String ?? "Unknown"
        let osVersion = record[DeviceFields.osVersion] as? String ?? "?"
        let appVersion = record[DeviceFields.appVersion] as? String ?? "?"
        let lastActiveDate = record[DeviceFields.lastActiveDate] as? Date ?? .distantPast
        let lastModified = record[DeviceFields.lastModified] as? Date ?? .distantPast
        let deviceSymbol = record[DeviceFields.deviceSymbol] as? String ?? "desktopcomputer"

        return SyncedDevice(
            id: id,
            deviceName: deviceName,
            modelIdentifier: modelIdentifier,
            platform: platform,
            osVersion: osVersion,
            appVersion: appVersion,
            lastActiveDate: lastActiveDate,
            lastModifiedDate: lastModified,
            deviceSymbol: deviceSymbol
        )
    }

    // Convenience typealias for shorter field access
    private typealias DeviceFields = CloudKitRecordTypes.DeviceFields
}

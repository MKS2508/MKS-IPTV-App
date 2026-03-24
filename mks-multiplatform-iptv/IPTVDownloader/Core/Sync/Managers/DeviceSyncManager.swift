//
//  DeviceSyncManager.swift
//  mks-multiplatform-iptv
//
//  Manages device registration and discovery in CloudKit.
//

import Foundation
import CloudKit

/// Registers the current device in CloudKit and fetches all synced devices.
///
/// Each app launch calls `registerCurrentDevice()` to upsert a `SyncedDevice`
/// CKRecord with the current timestamp. The Settings screen uses
/// `fetchSyncedDevices()` to display all devices sharing the same iCloud account.
@MainActor
final class DeviceSyncManager: ObservableObject {

    /// Singleton instance.
    static let shared = DeviceSyncManager()

    /// All synced devices, sorted by `lastActiveDate` descending.
    @Published private(set) var syncedDevices: [SyncedDevice] = []

    /// Whether a fetch/register operation is in progress.
    @Published private(set) var isLoading = false

    /// The CloudKit sync engine (actor-isolated).
    private let engine = CloudKitSyncEngine()

    private init() {}

    // MARK: - Public API

    /// The current device from the list, matched by UUID.
    var currentDevice: SyncedDevice? {
        syncedDevices.first { $0.id == DeviceIdentifier.deviceUUID }
    }

    /// All devices except the current one.
    var otherDevices: [SyncedDevice] {
        syncedDevices.filter { $0.id != DeviceIdentifier.deviceUUID }
    }

    /// Registers or updates the current device's CKRecord in CloudKit.
    ///
    /// Called on every app launch to keep the `lastActiveDate` fresh.
    /// Uses `saveRecords` (which applies `.changedKeys` save policy) instead of
    /// `saveRecord` so that re-registering an already-known device updates the
    /// existing record rather than failing with "record already exists".
    func registerCurrentDevice() async {
        let device = SyncedDevice.current()
        let record = device.toRecord(in: CloudKitContainer.zoneID)

        do {
            _ = try await engine.saveRecords([record])
            MKSLog.network.info("[DeviceSync] Registered device: \(device.deviceName) (\(device.platform))")
        } catch {
            MKSLog.network.error("[DeviceSync] Failed to register device: \(error)")
        }
    }

    /// Fetches all `SyncedDevice` records from CloudKit.
    ///
    /// Updates the published `syncedDevices` array. Sorted by `lastActiveDate`
    /// descending so the most recently active device appears first.
    func fetchSyncedDevices() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let records = try await engine.fetchRecordsViaZoneChanges(ofType: CloudKitRecordTypes.syncedDevice)
            let devices = records.compactMap { SyncedDevice.fromRecord($0) }
                .sorted { $0.lastActiveDate > $1.lastActiveDate }
            syncedDevices = devices
            MKSLog.network.info("[DeviceSync] Fetched \(devices.count) synced device(s)")
        } catch {
            MKSLog.network.error("[DeviceSync] Failed to fetch devices: \(error)")
        }
    }

    /// Removes a device record from CloudKit.
    ///
    /// Used from the context menu in SyncedDevicesView to clean up stale devices.
    /// - Parameter device: The device to remove.
    func removeDevice(_ device: SyncedDevice) async {
        let recordID = CKRecord.ID(
            recordName: device.id.uuidString,
            zoneID: CloudKitContainer.zoneID
        )

        do {
            try await engine.deleteRecord(recordID)
            syncedDevices.removeAll { $0.id == device.id }
            MKSLog.network.info("[DeviceSync] Removed device: \(device.deviceName)")
        } catch {
            MKSLog.network.error("[DeviceSync] Failed to remove device: \(error)")
        }
    }
}

//
//  SyncedDevicesView.swift
//  mks-multiplatform-iptv
//
//  Displays all devices synced via iCloud.
//

import SwiftUI
import IPTVCore

/// Shows all devices registered in CloudKit for the current iCloud account.
///
/// The current device is highlighted with a "This Device" badge. Other devices
/// display their platform SF Symbol, name, OS version, and relative last-active
/// time. Stale devices can be removed via context menu.
struct SyncedDevicesView: View {
    @StateObject private var deviceManager = DeviceSyncManager.shared

    var body: some View {
        Section {
            if deviceManager.isLoading && deviceManager.syncedDevices.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading devices...")
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if deviceManager.syncedDevices.isEmpty {
                emptyState
            } else {
                devicesList
            }
        } header: {
            HStack {
                Label("Synced Devices", systemImage: "laptopcomputer.and.iphone")
                Spacer()
                if deviceManager.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button {
                    Task { await deviceManager.fetchSyncedDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(deviceManager.isLoading)
            }
        }
        .task {
            await deviceManager.fetchSyncedDevices()
        }
    }

    // MARK: - Devices List

    @ViewBuilder
    private var devicesList: some View {
        // Current device first
        if let current = deviceManager.currentDevice {
            DeviceRow(device: current, isCurrentDevice: true)
        }

        // Other devices
        ForEach(deviceManager.otherDevices) { device in
            DeviceRow(device: device, isCurrentDevice: false)
                .contextMenu {
                    Button("Remove Device", role: .destructive) {
                        Task { await deviceManager.removeDevice(device) }
                    }
                }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No synced devices found")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Sign in to iCloud and enable sync to see your devices.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Device Row

/// A single row displaying a synced device's info.
private struct DeviceRow: View {
    let device: SyncedDevice
    let isCurrentDevice: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.deviceSymbol)
                .font(.title2)
                .foregroundStyle(isCurrentDevice ? .accent : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.body)
                        .fontWeight(isCurrentDevice ? .semibold : .regular)

                    if isCurrentDevice {
                        Text("This Device")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text("\(device.platform) \(device.osVersion)")
                    Text("·")
                    Text("v\(device.appVersion)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !isCurrentDevice {
                    Text("Last active: \(relativeTime(device.lastActiveDate))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Formats a date as a relative time string (e.g. "2 hours ago").
    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

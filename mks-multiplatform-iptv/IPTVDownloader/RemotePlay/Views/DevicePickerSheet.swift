//
//  DevicePickerSheet.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - SwiftUI sheet for remote device selection
//

import SwiftUI

/// Full modal picker for browsing and selecting remote playback devices.
struct DevicePickerSheet: View {

    // MARK: - Properties

    /// Available devices from discovery.
    let devices: [RemoteDevice]

    /// Whether discovery is in progress.
    let isDiscovering: Bool

    /// Currently connected device (if any).
    let selectedDevice: RemoteDevice?

    /// Callback when device is selected.
    let onDeviceSelected: (RemoteDevice) -> Void

    /// Callback to refresh discovery.
    let onRefresh: () -> Void

    /// Callback to dismiss sheet.
    let onDismiss: () -> Void

    // MARK: - State

    @State private var hoveredDeviceId: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // Discovery status section
                Section {
                    if isDiscovering && devices.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Searching for devices...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else if devices.isEmpty {
                        ContentUnavailableView(
                            "No Devices Found",
                            systemImage: "tv.slash",
                            description: Text("Make sure your TV or media player is on and connected to the same WiFi network.")
                        )
                    } else {
                        // Filter out connected device from available list to avoid duplicate
                        let availableDevices = devices.filter { $0.id != selectedDevice?.id }
                        ForEach(availableDevices) { device in
                            let isSupportedType = true
                            DeviceRow(
                                device: device,
                                isSelected: selectedDevice?.id == device.id,
                                isHovered: hoveredDeviceId == device.id,
                                isUnsupported: !isSupportedType
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSupportedType {
                                    onDeviceSelected(device)
                                }
                            }
                            .onHover { isHovered in
                                hoveredDeviceId = isHovered ? device.id : nil
                            }
                            .opacity(isSupportedType ? 1.0 : 0.6)
                        }
                    }
                } header: {
                    HStack {
                        Text("Available Devices")
                        Spacer()
                        if isDiscovering {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                } footer: {
                    Text("Tap a device to connect and start casting")
                }

                // Connected device section
                if let connected = selectedDevice {
                    Section {
                        DeviceRow(
                            device: connected,
                            isSelected: true,
                            isHovered: false
                        )
                    } header: {
                        Text("Connected Device")
                    }
                }
            }
            .navigationTitle("Cast to Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isDiscovering)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.sidebar)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }
}

// MARK: - Device Row

private struct DeviceRow: View {

    let device: RemoteDevice
    let isSelected: Bool
    let isHovered: Bool
    var isUnsupported: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            Image(systemName: device.type.icon)
                .font(.title2)
                .foregroundStyle(isSelected ? device.type.accentColor : .secondary)
                .frame(width: 36)

            // Device info
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(device.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(device.type.accentColor.opacity(0.15))
                        .foregroundColor(device.type.accentColor)
                        .cornerRadius(4)

                    if isUnsupported {
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    } else if let manufacturer = device.manufacturer {
                        Text(manufacturer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isUnsupported {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            } else if isHovered {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    DevicePickerSheet(
        devices: [
            RemoteDevice.dlna(
                id: "uuid:1234",
                name: "Living Room TV",
                capabilities: .full,
                controlURL: "http://192.168.1.100:8080/control"
            ),
            RemoteDevice.dlna(
                id: "uuid:5678",
                name: "Bedroom TV",
                capabilities: [.video, .audio],
                controlURL: "http://192.168.1.101:8080/control"
            )
        ],
        isDiscovering: false,
        selectedDevice: nil,
        onDeviceSelected: { _ in },
        onRefresh: {},
        onDismiss: {}
    )
}

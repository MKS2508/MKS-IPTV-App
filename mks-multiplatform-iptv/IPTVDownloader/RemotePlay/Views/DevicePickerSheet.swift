//
//  DevicePickerSheet.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - SwiftUI sheet for remote device selection
//

import SwiftUI
import IPTVCore

/// Full modal picker for browsing and selecting remote playback devices.
struct DevicePickerSheet: View {

    // MARK: - Environment

    /// Observe the manager directly so this sheet tracks device changes in its own body.
    @Environment(RemotePlayManager.self) private var remotePlayManager

    // MARK: - Properties

    /// Callback when device is selected.
    let onDeviceSelected: (RemoteDevice) -> Void

    /// Callback to refresh discovery.
    let onRefresh: () -> Void

    /// Callback to dismiss sheet.
    let onDismiss: () -> Void

    // MARK: - Computed

    private var devices: [RemoteDevice] { remotePlayManager.discoveredDevices }
    private var isDiscovering: Bool { remotePlayManager.isDiscovering }
    private var selectedDevice: RemoteDevice? { remotePlayManager.connectedDevice }

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
                            .contextMenu {
                                DeviceProtocolMenu(device: device, manager: remotePlayManager)
                            }
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
                    Text("Tap a device to connect and start playback")
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
            .navigationTitle("Remote Playback")
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
        .onAppear {
            // Start discovery lazily when the picker opens (not at app launch).
            remotePlayManager.ensureDiscoveryActive()
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

    /// Display label for the effective transport protocol.
    private var protocolLabel: String {
        let proto = device.effectiveTransport
        let isOverridden = device.transportOverride != nil
        let label = proto == .dlna ? "DLNA" : "Cast"
        return isOverridden ? "\(label) (forced)" : label
    }

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

                HStack(spacing: 6) {
                    // Device type badge
                    Text(device.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(device.type.accentColor.opacity(0.15))
                        .foregroundColor(device.type.accentColor)
                        .cornerRadius(4)

                    // Protocol badge
                    Text(protocolLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.15))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)

                    // Capability indicators
                    CapabilityIndicators(capabilities: device.capabilities)
                }

                if isUnsupported {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else if device.hasLimitedCapabilities {
                    Label("Limited (no transport control)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if let manufacturer = device.manufacturer {
                    Text(manufacturer)
                        .font(.caption)
                        .foregroundColor(.secondary)
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

// MARK: - Capability Indicators

/// Small SF Symbol indicators showing device capabilities at a glance.
private struct CapabilityIndicators: View {
    let capabilities: DeviceCapabilities

    var body: some View {
        HStack(spacing: 4) {
            if capabilities.contains(.seeking) {
                Image(systemName: "forward.fill")
                    .help("Seeking supported")
            }
            if capabilities.contains(.volumeControl) {
                Image(systemName: "speaker.wave.2.fill")
                    .help("Volume control")
            }
            if capabilities.contains(.pause) {
                Image(systemName: "pause.fill")
                    .help("Pause supported")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Protocol Override Menu

/// Context menu allowing the user to force a specific transport protocol on a device.
private struct DeviceProtocolMenu: View {
    let device: RemoteDevice
    let manager: RemotePlayManager

    var body: some View {
        Section("Transport Protocol") {
            Button {
                setOverride(nil)
            } label: {
                Label(
                    "Auto (detected: \(device.type.transportProtocol == .dlna ? "DLNA" : "Cast"))",
                    systemImage: device.transportOverride == nil ? "checkmark" : ""
                )
            }

            Button {
                setOverride(.dlna)
            } label: {
                Label(
                    "Force DLNA",
                    systemImage: device.transportOverride == .dlna ? "checkmark" : ""
                )
            }

            Button {
                setOverride(.castV2)
            } label: {
                Label(
                    "Force Cast V2",
                    systemImage: device.transportOverride == .castV2 ? "checkmark" : ""
                )
            }
        }
    }

    private func setOverride(_ proto: TransportProtocol?) {
        if let idx = manager.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            manager.discoveredDevices[idx].transportOverride = proto
        }
    }
}

// MARK: - Preview

#Preview {
    DevicePickerSheet(
        onDeviceSelected: { _ in },
        onRefresh: {},
        onDismiss: {}
    )
    .environment(RemotePlayManager.shared)
}

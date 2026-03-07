//
//  RemotePlayButton.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - SwiftUI button for remote device selection
//

import SwiftUI

/// Button that displays available remote devices in a Menu for device selection.
/// Shows cast icon, when tapped shows a menu with discovered devices.
struct RemotePlayButton: View {

    // MARK: - Environment

    @Environment(RemotePlayManager.self) private var remotePlayManager

    // MARK: - State

    @State private var showingDevicePicker = false

    // MARK: - Body

    var body: some View {
        Button {
            if remotePlayManager.connectedDevice != nil {
                // Disconnect from current device
                Task {
                    await remotePlayManager.disconnect()
                }
            } else {
                showingDevicePicker = true
            }
        } label: {
            HStack(spacing: 6) {
                if remotePlayManager.connectedDevice != nil {
                    // Show connected device
                    if let deviceName = remotePlayManager.connectedDevice?.name {
                        Text(deviceName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "tv.fill")
                        .foregroundStyle(.primary)
                } else {
                    // Show cast icon
                    if remotePlayManager.isDiscovering {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                    }
                    Image(systemName: "tv")
                }
            }
        }
        .sheet(isPresented: $showingDevicePicker) {
            DevicePickerSheet(
                devices: remotePlayManager.discoveredDevices,
                isDiscovering: remotePlayManager.isDiscovering,
                selectedDevice: remotePlayManager.connectedDevice,
                onDeviceSelected: { device in
                    Task {
                        showingDevicePicker = false
                        try? await remotePlayManager.connect(to: device)
                    }
                },
                onRefresh: {
                    remotePlayManager.refreshDiscovery()
                },
                onDismiss: {
                    showingDevicePicker = false
                }
            )
        }
        .onAppear {
            // Start discovery when button appears
            remotePlayManager.startDiscovery()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        RemotePlayButton()
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
    }
    .frame(width: 300, height: 200)
    .padding()
    .environment(RemotePlayManager.shared)
}

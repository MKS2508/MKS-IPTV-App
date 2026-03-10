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
    @State private var connectionError: RemotePlayError?
    @State private var hasStartedDiscovery = false

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
                if let device = remotePlayManager.connectedDevice {
                    // Show connected device with type-specific icon
                    Text(device.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: device.type.icon)
                        .foregroundStyle(device.type.accentColor)
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
                onDeviceSelected: { device in
                    showingDevicePicker = false
                    Task {
                        do {
                            try await remotePlayManager.connect(to: device)
                        } catch let error as RemotePlayError {
                            connectionError = error
                        } catch {
                            connectionError = .unknown(error.localizedDescription)
                        }
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
        .alert(
            "Connection Failed",
            isPresented: Binding(
                get: { connectionError != nil },
                set: { if !$0 { connectionError = nil } }
            ),
            presenting: connectionError
        ) { _ in
            Button("OK") { connectionError = nil }
        } message: { error in
            Text(error.errorDescription ?? "Unknown error")
        }
        .onAppear {
            // Start discovery only once (not on every navigation appear)
            if !hasStartedDiscovery {
                hasStartedDiscovery = true
                remotePlayManager.startDiscovery()
            }
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

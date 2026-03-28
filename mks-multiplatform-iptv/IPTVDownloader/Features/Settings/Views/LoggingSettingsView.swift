//
//  LoggingSettingsView.swift
//  mks-multiplatform-iptv
//
//  Settings panel for controlling log directory, per-subsystem levels,
//  and log file management.
//

import SwiftUI

#if os(macOS)
/// macOS settings view for centralized log configuration.
struct LoggingSettingsView: View {
    @State private var refreshToken = UUID()

    private var config: MKSLogConfig { .shared }

    var body: some View {
        Form {
            storageSection
            levelsSection
            filesSection
            remoteDebugSection
        }
        .formStyle(.grouped)
        .navigationTitle("Logging")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Storage Section

    @ViewBuilder
    private var storageSection: some View {
        Section {
            LabeledContent("Directory") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(config.logDirectory)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: config.logDirectory)
                        }
                        .controlSize(.small)

                        Button("Reset to Default") {
                            config.resetLogDirectory()
                            config.ensureLogDirectoryExists()
                            refreshToken = UUID()
                        }
                        .controlSize(.small)
                    }
                }
            }

            LabeledContent("Max File Size") {
                Text(ByteCountFormatter.string(fromByteCount: Int64(config.maxFileSize), countStyle: .file))
                    .foregroundColor(.secondary)
            }
        } header: {
            Label("Storage", systemImage: "folder")
        }
    }

    // MARK: - Levels Section

    @ViewBuilder
    private var levelsSection: some View {
        Section {
            ForEach(MKSLogConfig.Subsystem.allCases) { subsystem in
                SubsystemLevelRow(subsystem: subsystem)
            }
        } header: {
            Label("Log Levels", systemImage: "slider.horizontal.3")
        } footer: {
            Text("Changes take effect immediately for new log entries.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Files Section

    @ViewBuilder
    private var filesSection: some View {
        Section {
            // Show unique files only (transmux+ffmpeg share a file)
            let uniqueSubsystems: [MKSLogConfig.Subsystem] = [.transmux, .player, .cast, .live]
            ForEach(uniqueSubsystems) { subsystem in
                LabeledContent(subsystem.displayName) {
                    let size = config.fileSize(for: subsystem)
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .foregroundColor(.secondary)
                        .id(refreshToken)
                }
            }

            Button(role: .destructive) {
                config.clearAllLogs()
                refreshToken = UUID()
            } label: {
                Label("Clear All Logs", systemImage: "trash")
            }
        } header: {
            Label("Log Files", systemImage: "doc.text")
        }
    }

    // MARK: - Remote Debug Section

    @ViewBuilder
    private var remoteDebugSection: some View {
        Section {
            // macOS is a RECEIVER — shows listener status + connected iOS devices
            let receiver = RemoteLogReceiver.shared

            // Listener status
            LabeledContent("Receiver Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(receiver.isListening ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(receiver.isListening ? "Listening on port \(receiver.port)" : "Off")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Start/stop
            HStack {
                Button(receiver.isListening ? "Stop Receiver" : "Start Receiver") {
                    if receiver.isListening {
                        receiver.stop()
                    } else {
                        receiver.start()
                    }
                    refreshToken = UUID()
                }
                .controlSize(.small)

                Spacer()

                Text("Publishes _mksiptv-debug._tcp on LAN")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }

            // Connected devices
            if receiver.connectedDevices.isEmpty {
                LabeledContent("Connected Devices") {
                    Text("None — open the iOS app on the same network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(receiver.connectedDevices, id: \.id) { device in
                    LabeledContent(device.name) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(device.systemVersion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("v\(device.appVersion)")
                                .font(.caption2)
                                .foregroundColor(.tertiary)
                            Text("Connected \(device.connectedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundColor(.tertiary)
                        }
                    }
                }
            }

            // Manual connect (to send commands to a remote viewer/Elysia)
            manualConnectRow
        } header: {
            Label("Remote Debug", systemImage: "antenna.radiowaves.left.and.right")
        } footer: {
            Text("macOS receives logs from iOS devices on the same network via Bonjour + WebSocket. Logs appear in the Remote tab of the Log Inspector.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @State private var manualHost: String = ""
    @State private var manualPort: String = "3000"
    @State private var manualConnectStatus: String?

    @ViewBuilder
    private var manualConnectRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Connect (send logs to viewer)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("IP or hostname", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                TextField("Port", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Button("Connect") {
                    guard let port = UInt16(manualPort), !manualHost.isEmpty else {
                        manualConnectStatus = "Invalid host or port"
                        return
                    }
                    RemoteDebugService.shared.connectManually(host: manualHost, port: port)
                    manualConnectStatus = "Connecting to \(manualHost):\(port)..."
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            if let status = manualConnectStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Show RemoteDebugService state
            let service = RemoteDebugService.shared
            if service.isConnected {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Connected to \(service.viewerName ?? "viewer")")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            if let error = service.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Subsystem Level Row

/// A single row with a segmented picker for one subsystem's log level.
private struct SubsystemLevelRow: View {
    let subsystem: MKSLogConfig.Subsystem
    @State private var selectedLevel: MKSLogConfig.Level

    init(subsystem: MKSLogConfig.Subsystem) {
        self.subsystem = subsystem
        self._selectedLevel = State(initialValue: MKSLogConfig.shared.level(for: subsystem))
    }

    var body: some View {
        Picker(subsystem.displayName, selection: $selectedLevel) {
            ForEach(MKSLogConfig.Level.allCases) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedLevel) { _, newValue in
            MKSLogConfig.shared.setLevel(newValue, for: subsystem)
        }
    }
}
#endif

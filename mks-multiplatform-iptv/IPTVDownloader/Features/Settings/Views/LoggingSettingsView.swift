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

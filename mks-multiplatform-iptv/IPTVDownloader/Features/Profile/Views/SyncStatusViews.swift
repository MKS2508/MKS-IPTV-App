//
//  SyncStatusViews.swift
//  mks-multiplatform-iptv
//
//  SwiftUI views for displaying CloudKit sync status.
//

import SwiftUI

/// Compact sync status indicator showing an icon and label.
///
/// Displays the current `SyncStatus` as a system image with a
/// short localized description. Suitable for list rows and toolbars.
struct SyncStatusIndicator: View {
    let status: SyncStatus

    var body: some View {
        Label {
            Text(status.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            statusIcon
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .syncing:
            ProgressView()
                .controlSize(.mini)
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.red)
        case .offline:
            Image(systemName: "icloud.slash.fill")
                .foregroundStyle(.orange)
        case .unavailable:
            Image(systemName: "xmark.icloud.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// Expanded sync status view with last sync time and manual sync button.
///
/// Shows detailed sync information including the last successful sync
/// timestamp and provides a button to trigger a manual sync.
struct SyncStatusDetailView: View {
    @ObservedObject var manager: IPTVProfilesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SyncStatusIndicator(status: manager.syncStatus)
                Spacer()
                if manager.syncStatus.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if manager.pendingChangesCount > 0 {
                Text("\(manager.pendingChangesCount) pending change(s)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Toggle("iCloud Sync", isOn: $manager.isSyncEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Button {
                Task {
                    await manager.syncProfiles()
                }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(manager.syncStatus.isSyncing || !manager.isSyncEnabled)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }
}

/// Toolbar button that shows the current sync status.
///
/// Tapping the button triggers a manual sync. The icon animates
/// while a sync is in progress.
struct SyncToolbarItem: View {
    @ObservedObject var manager: IPTVProfilesManager

    var body: some View {
        Button {
            Task {
                await manager.syncProfiles()
            }
        } label: {
            toolbarIcon
        }
        .disabled(manager.syncStatus.isSyncing)
        .help(manager.syncStatus.localizedDescription)
    }

    @ViewBuilder
    private var toolbarIcon: some View {
        switch manager.syncStatus {
        case .idle:
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .symbolRenderingMode(.hierarchical)
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.rotate)
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
        case .offline:
            Image(systemName: "icloud.slash.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
        case .unavailable:
            Image(systemName: "xmark.icloud.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}

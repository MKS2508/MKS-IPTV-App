import SwiftUI
import IPTVCore
import TransmuxCore

// MARK: - Local File Action Sheet

struct LocalFileActionSheet: View {
    let file: LocalVideoFile
    let metadata: LocalFileMetadata
    let onDismiss: () -> Void
    let onEditMetadata: () -> Void
    let onConvert: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: file.fileTypeIcon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Actions
            VStack(spacing: 0) {
                actionRow(icon: "play.circle.fill", label: "Play") {
                    playFile()
                }

                actionRow(icon: "pencil", label: "Edit Metadata") {
                    onEditMetadata()
                }

                actionRow(icon: "arrow.triangle.2.circlepath", label: "Convert Format...") {
                    onConvert()
                }

                actionRow(icon: "folder", label: "Show in Finder") {
                    showInFinder()
                }

                Divider()

                actionRow(icon: "trash", label: "Remove from Library", isDestructive: true) {
                    showDeleteConfirmation = true
                }
            }
        }
        .frame(width: 320)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .confirmationDialog(
            "Remove \(metadata.displayName)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will not be deleted from disk.")
        }
    }

    private func actionRow(
        icon: String,
        label: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Text(label)
                    .font(.body)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
    private func playFile() {
        let player = PlayerFactory.shared.createPlayer(for: file.url)
        PlayerWindowManager.shared.present(player: player, title: metadata.displayName, metadata: nil)
        player.load(url: file.url)
        player.play()
        onDismiss()
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
        onDismiss()
    }
    #else
    private func playFile() {
        // iOS: use AVPlayerViewController or similar
        onDismiss()
    }

    private func showInFinder() {
        // iOS: share sheet or document picker
        onDismiss()
    }
    #endif
}

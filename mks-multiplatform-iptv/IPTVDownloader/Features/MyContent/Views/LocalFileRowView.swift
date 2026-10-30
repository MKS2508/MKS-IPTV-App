import SwiftUI
import IPTVCore

struct LocalFileRowView: View {
    let file: LocalVideoFile
    let effectiveDisplayName: String
    let onPlay: () -> Void
    let onShowActions: (CGPoint) -> Void

    init(
        file: LocalVideoFile,
        effectiveDisplayName: String,
        onPlay: @escaping () -> Void,
        onShowActions: @escaping (CGPoint) -> Void
    ) {
        self.file = file
        self.effectiveDisplayName = effectiveDisplayName
        self.onPlay = onPlay
        self.onShowActions = onShowActions
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.fileTypeIcon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(effectiveDisplayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(file.fileExtension.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .cornerRadius(4)

                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)

            // Action menu (macOS)
            #if os(macOS)
            Menu {
                Button("Edit Metadata...") {
                    onShowActions(.zero)
                }
                Button("Convert Format...") {
                    onShowActions(.zero)
                }
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
                }
                Divider()
                Button(role: .destructive) {
                    // Delete handled by action sheet
                } label: {
                    Text("Remove from Library")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .onTapGesture(count: 2) {
                onShowActions(.zero)
            }
            #else
            Button {
                onShowActions(.zero)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            #endif
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("Play", systemImage: "play.circle")
            }

            Divider()

            Button {
                onShowActions(.zero)
            } label: {
                Label("Edit Metadata...", systemImage: "pencil")
            }

            Button {
                // Convert handled by action sheet
                onShowActions(.zero)
            } label: {
                Label("Convert Format...", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            Button {
                #if os(macOS)
                NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }
}

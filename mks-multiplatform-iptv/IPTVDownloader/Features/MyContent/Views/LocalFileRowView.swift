import SwiftUI
import IPTVCore

struct LocalFileRowView: View {
    let file: LocalVideoFile
    let onPlay: () -> Void
    let onRemove: (() -> Void)?
    
    init(file: LocalVideoFile, onPlay: @escaping () -> Void, onRemove: (() -> Void)? = nil) {
        self.file = file
        self.onPlay = onPlay
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.fileTypeIcon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
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
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.secondary.opacity(0.1))
        .cornerRadius(8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onRemove = onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

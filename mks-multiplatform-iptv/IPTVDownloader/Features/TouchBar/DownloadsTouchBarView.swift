import SwiftUI

#if os(macOS)
struct DownloadsTouchBarView: View {
    let activeDownloads: Int
    let progress: Double
    let speedText: String
    let etaText: String
    let isPaused: Bool

    let onPauseResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Descargas activas
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("\(activeDownloads)")
                    .font(.system(size: 11, weight: .bold))
                Text(activeDownloads == 1 ? "download" : "downloads")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .layoutPriority(1)

            // Progreso
            VStack(spacing: 2) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .scaleEffect(y: 1.4)
                    .clipShape(Capsule())
                    .layoutPriority(2)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }

            // Velocidad y ETA
            HStack(spacing: 10) {
                VStack(spacing: -2) {
                    Text(speedText)
                        .font(.system(size: 10, weight: .semibold))
                    Text("Speed")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                VStack(spacing: -2) {
                    Text(etaText)
                        .font(.system(size: 10, weight: .semibold))
                    Text("ETA")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
            .layoutPriority(1)

            // Controles
            HStack(spacing: 6) {
                Button(action: onPauseResume) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .foregroundColor(.white)
                        .padding(5)
                        .background(isPaused ? Color.green : Color.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        
        
    }
}
#endif
#if os(macOS)
struct DownloadsTouchBarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DownloadsTouchBarView(
                activeDownloads: 3,
                progress: 0.65,
                speedText: "2.5 MB/s",
                etaText: "05:23",
                isPaused: false,
                onPauseResume: {},
                onCancel: {}
            )
            .previewDisplayName("Active Downloads")
        }
        .previewLayout(.fixed(width: 1080, height: 30))
        .background(Color.black.opacity(0.85))
    }
}
#endif

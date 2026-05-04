import SwiftUI
import IPTVCore

/// Unified VLC button for use in movies, series, episodes, and live channels.
/// Handles UI, logic, hiding if VLC unavailable, and URL construction.
struct OpenInVLCButton: View {
    /// Closure that returns the stream URL string to open in VLC
    let urlProvider: () -> String?
    /// Optional label override (defaults to "VLC")
    var label: String = "VLC"
    /// Optional action after opening (for analytics, etc)
    var onOpened: (() -> Void)? = nil

    var body: some View {
        if VLCHelper.isVLCInstalled(), let urlString = urlProvider(), let _ = URL(string: urlString) {
            Button(action: {
                VLCHelper.openInVLC(url: urlString)
                onOpened?()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 18))
                    Text(label)
                        .font(.system(size: 18, weight: .semibold))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
            }
        }
    }
}

import SwiftUI

struct DownloadButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .imageScale(.large)
                Text("Download")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: 200)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed ? Color.accentColor.opacity(0.8) : (isHovered ? Color.accentColor.opacity(0.9) : Color.accentColor))
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

import SwiftUI
import IPTVCore

struct PreviewTest: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Preview Test")
                .font(.title)
            Text("Si ves esto, los previews funcionan")
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    PreviewTest()
}

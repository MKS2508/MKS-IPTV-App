import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text("(\(count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.bottom, 8)
    }
}

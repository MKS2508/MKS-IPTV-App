import SwiftUI

#if DEBUG

// MARK: - Standalone Preview Components

struct MediaListViewPreview: View {
    var body: some View {
        VStack(spacing: 30) {
            Text("MediaListView Components")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Divider()
            
            // Content Type Buttons
            VStack(alignment: .leading, spacing: 10) {
                Text("Content Type Selector")
                    .font(.headline)
                
                HStack(spacing: 10) {
                    ContentTypeButtonPreview(
                        title: "All",
                        systemImage: "play.rectangle.on.rectangle.fill",
                        isSelected: true
                    )
                    
                    ContentTypeButtonPreview(
                        title: "Movies",
                        systemImage: "film.fill",
                        isSelected: false
                    )
                    
                    ContentTypeButtonPreview(
                        title: "Series",
                        systemImage: "tv.fill",
                        isSelected: false
                    )
                }
            }
            
            Divider()
            
            // Category Chip
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected Categories")
                    .font(.headline)
                
                HStack {
                    SelectedCategoryChipPreview(
                        categoryName: "Action"
                    )
                    
                    SelectedCategoryChipPreview(
                        categoryName: "Drama"
                    )
                    
                    SelectedCategoryChipPreview(
                        categoryName: "Sci-Fi & Fantasy"
                    )
                }
            }
            
            Divider()
            
            // Loading States
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading States")
                    .font(.headline)
                
                HStack(spacing: 30) {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                        Text("Error")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack {
                        Image(systemName: "film.slash")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Empty")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 600, height: 500)
    }
}

// Preview of ContentTypeButton
struct ContentTypeButtonPreview: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    
    var body: some View {
        Text(title)
            .font(.callout)
            .fontWeight(.semibold)
            .frame(minWidth: 80)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 3)
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
            .foregroundColor(isSelected ? .white : .primary)
    }
}

// Preview of SelectedCategoryChip
struct SelectedCategoryChipPreview: View {
    let categoryName: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(categoryName)
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.tail)
            
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.2))
        )
        .overlay(
            Capsule()
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview Provider

struct MediaListViewPreview_Previews: PreviewProvider {
    static var previews: some View {
        MediaListViewPreview()
            .preferredColorScheme(.dark)
            .previewDisplayName("MediaListView Components")
    }
}

#endif

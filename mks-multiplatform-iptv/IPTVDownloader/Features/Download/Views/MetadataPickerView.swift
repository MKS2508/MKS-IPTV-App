import SwiftUI

/// Interactive metadata picker and editor.
///
/// Displays all metadata candidates from providers as selectable cards.
/// The user picks one, optionally edits fields, then confirms to write tags.
struct MetadataPickerView: View {
    let downloadItem: DownloadItem
    let onConfirm: (MetadataResult) -> Void
    let onDismiss: () -> Void

    @State private var selectedCandidateId: UUID?
    @State private var editableMetadata: EditableMetadata?
    @State private var isEditing = false

    private var candidates: [ScoredMetadataResult] {
        downloadItem.metadataCandidates
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()

            if isEditing, let _ = editableMetadata {
                // Editing form
                metadataEditForm
            } else {
                // Candidate selection list
                candidatesList
            }

            Divider()
            // Action bar
            actionBar
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(.ultraThinMaterial)
        .onAppear {
            // Pre-select the best match
            if let first = candidates.first {
                selectedCandidateId = first.id
                editableMetadata = EditableMetadata(from: first.result)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Metadata for: \(downloadItem.title)")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(candidates.count) results from providers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }

    // MARK: - Candidates List

    private var candidatesList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if candidates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No metadata candidates found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(candidates) { candidate in
                        MetadataCandidateCard(
                            candidate: candidate,
                            isSelected: selectedCandidateId == candidate.id
                        )
                        .onTapGesture {
                            selectedCandidateId = candidate.id
                            editableMetadata = EditableMetadata(from: candidate.result)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Edit Form

    private var metadataEditForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Edit Metadata")
                        .font(.headline)
                    Spacer()
                    Button("Back to Results") {
                        isEditing = false
                    }
                    .font(.caption)
                }

                if editableMetadata != nil {
                    Group {
                        metadataTextField("Title", text: binding(\.title))
                        metadataTextField("Original Title", text: optionalBinding(\.originalTitle))
                        metadataTextField("Director", text: optionalBinding(\.director))

                        HStack(spacing: 12) {
                            metadataIntField("Year", value: optionalIntBinding(\.year))
                            metadataIntField("Runtime (min)", value: optionalIntBinding(\.runtimeMinutes))
                        }

                        metadataTextField("Genre (comma-separated)",
                                          text: Binding(
                                            get: { editableMetadata?.genre.joined(separator: ", ") ?? "" },
                                            set: { newValue in
                                                editableMetadata?.genre = newValue.components(separatedBy: ",")
                                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                                    .filter { !$0.isEmpty }
                                            }
                                          ))

                        metadataTextField("Cast (comma-separated)",
                                          text: Binding(
                                            get: { editableMetadata?.cast.joined(separator: ", ") ?? "" },
                                            set: { newValue in
                                                editableMetadata?.cast = newValue.components(separatedBy: ",")
                                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                                    .filter { !$0.isEmpty }
                                            }
                                          ))

                        metadataDoubleField("Rating", value: optionalDoubleBinding(\.rating))
                        metadataTextField("Content Rating", text: optionalBinding(\.contentAdvisoryRating))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Plot")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: Binding(
                                get: { editableMetadata?.plot ?? "" },
                                set: { editableMetadata?.plot = $0.isEmpty ? nil : $0 }
                            ))
                            .frame(minHeight: 80)
                            .font(.body)
                            .padding(4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }

                        metadataTextField("Poster URL", text: optionalBinding(\.posterURL))
                        metadataTextField("IMDB ID", text: optionalBinding(\.imdbId))
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            if !isEditing {
                Button("Edit") {
                    isEditing = true
                }
                .disabled(editableMetadata == nil)
            }

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Write Tags") {
                guard let metadata = editableMetadata else { return }
                onConfirm(metadata.toMetadataResult())
            }
            .disabled(editableMetadata == nil)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Form Helpers

    private func metadataTextField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func metadataIntField(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: value)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }

    private func metadataDoubleField(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: value)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    // MARK: - Binding Helpers

    private func binding(_ keyPath: WritableKeyPath<EditableMetadata, String>) -> Binding<String> {
        Binding(
            get: { editableMetadata?[keyPath: keyPath] ?? "" },
            set: { editableMetadata?[keyPath: keyPath] = $0 }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<EditableMetadata, String?>) -> Binding<String> {
        Binding(
            get: { editableMetadata?[keyPath: keyPath] ?? "" },
            set: { editableMetadata?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func optionalIntBinding(_ keyPath: WritableKeyPath<EditableMetadata, Int?>) -> Binding<String> {
        Binding(
            get: {
                if let val = editableMetadata?[keyPath: keyPath] {
                    return String(val)
                }
                return ""
            },
            set: { editableMetadata?[keyPath: keyPath] = Int($0) }
        )
    }

    private func optionalDoubleBinding(_ keyPath: WritableKeyPath<EditableMetadata, Double?>) -> Binding<String> {
        Binding(
            get: {
                if let val = editableMetadata?[keyPath: keyPath] {
                    return String(format: "%.1f", val)
                }
                return ""
            },
            set: { editableMetadata?[keyPath: keyPath] = Double($0) }
        )
    }
}

// MARK: - Metadata Candidate Card

/// A single selectable metadata result card showing provider, match score, and key info.
struct MetadataCandidateCard: View {
    let candidate: ScoredMetadataResult
    let isSelected: Bool

    private var result: MetadataResult { candidate.result }

    var body: some View {
        HStack(spacing: 12) {
            // Poster thumbnail
            if let posterURL = result.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 75)
                            .cornerRadius(6)
                    } else {
                        posterPlaceholder
                    }
                }
            } else {
                posterPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    if let year = result.year {
                        Text("(\(String(year)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    // Provider badge
                    Text(result.providerName)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(providerColor)
                        .cornerRadius(4)

                    // Match score
                    Text("\(candidate.matchPercentage)% match")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let rating = result.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                        }
                    }
                }

                if !result.genre.isEmpty {
                    Text(result.genre.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let director = result.director, !director.isEmpty {
                    Text(director)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 50, height: 75)
            .overlay(
                Image(systemName: "film")
                    .font(.caption)
                    .foregroundColor(.secondary)
            )
    }

    private var providerColor: Color {
        switch result.providerName {
        case "TMDB": return .blue
        case "iTunes Search": return .pink
        case "TheTVDB": return .green
        default: return .gray
        }
    }
}

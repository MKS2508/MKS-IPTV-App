import SwiftUI
import IPTVCore

struct SeriesEpisodeURLView: View {
    let serie: Serie
    let categoryName: String
    @ObservedObject var viewModel: DebugStreamingViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFormat: CategoryURLFormat = .text
    @State private var isGenerating = false
    @State private var generatedContent = ""
    @State private var showingPreview = false
    @State private var episodeDetails: SerieDetail?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                Divider()
                
                // Series info
                seriesInfoSection
                
                Divider()
                
                // Episode preview
                if let details = episodeDetails {
                    episodePreviewSection(details: details)
                    Divider()
                }
                
                // Format and actions
                actionsSection
                
                // Progress indicator
                if isGenerating {
                    ProgressView("Generating episode URLs...")
                        .padding()
                }
            }
            .navigationTitle("Series Episode URLs")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: 1000, 
               minHeight: 500, idealHeight: 700, maxHeight: 900)
        .task {
            await loadEpisodeDetails()
        }
        .sheet(isPresented: $showingPreview) {
            previewView
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generate episode URLs for series")
                .font(.headline)
            
            Text("This will fetch all episodes and generate individual streaming URLs")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    // MARK: - Series Info Section
    
    private var seriesInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tv.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(serie.name)
                        .font(.headline)
                    
                    HStack {
                        Text("Category: \(categoryName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Series ID: \(serie.seriesId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            if serie.rating5Based > 0 {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", serie.rating5Based))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Episode Preview Section
    
    private func episodePreviewSection(details: SerieDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episode Overview")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(details.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }), id: \.id) { season in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Season \(season.seasonNumber)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                if let episodes = details.episodes[season.id] {
                                    Text("\(episodes.count) episodes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let episodes = details.episodes[season.id] {
                                let sampleEpisodes = Array(episodes.sorted(by: { $0.episodeNum < $1.episodeNum }).prefix(3))
                                ForEach(sampleEpisodes, id: \.id) { episode in
                                    HStack {
                                        Text("E\(episode.episodeNum)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 30, alignment: .leading)
                                        
                                        Text(episode.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Text(episode.containerExtension)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.leading, 16)
                                }
                                
                                if episodes.count > 3 {
                                    Text("... and \(episodes.count - 3) more episodes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 16) {
            // Format selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Output Format")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Picker("Format", selection: $selectedFormat) {
                    Label("Text Format", systemImage: "doc.text").tag(CategoryURLFormat.text)
                    Label("JSON Format", systemImage: "doc.plaintext").tag(CategoryURLFormat.json)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Preview") {
                    Task {
                        await generateAndPreview()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episodeDetails == nil || isGenerating)
                
                Button("Copy to Clipboard") {
                    Task {
                        await generateAndCopy()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(episodeDetails == nil || isGenerating)
                
                #if os(macOS)
                Button("Export to File") {
                    Task {
                        await generateAndExport()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episodeDetails == nil || isGenerating)
                #endif
            }
            
            // Episode count info
            if let details = episodeDetails {
                let totalEpisodes = details.episodes.values.reduce(0) { $0 + $1.count }
                Text("\(totalEpisodes) episodes across \(details.seasons.count) seasons")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Preview View
    
    private var previewView: some View {
        NavigationView {
            ScrollView {
                Text(generatedContent)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Episode URLs Preview")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingPreview = false }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        copyToClipboard(generatedContent)
                        showingPreview = false
                    }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 900, maxWidth: 1200,
               minHeight: 400, idealHeight: 600, maxHeight: 800)
    }
    
    // MARK: - Actions
    
    private func loadEpisodeDetails() async {
        viewModel.log("🔍 Loading episode details for: \(serie.name)", type: .info)
        
        do {
            episodeDetails = try await viewModel.movieService.fetchSeriesDetails(seriesId: serie.seriesId)
            let totalEpisodes = episodeDetails?.episodes.values.reduce(0) { $0 + $1.count } ?? 0
            viewModel.log("✅ Loaded \(totalEpisodes) episodes for \(serie.name)", type: .success)
        } catch {
            viewModel.log("❌ Failed to load episode details: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func generateAndPreview() async {
        guard episodeDetails != nil else { return }
        
        isGenerating = true
        generatedContent = await viewModel.generateSeriesEpisodeURLs(
            for: serie,
            categoryName: categoryName,
            format: selectedFormat
        )
        isGenerating = false
        showingPreview = true
    }
    
    private func generateAndCopy() async {
        guard episodeDetails != nil else { return }
        
        isGenerating = true
        let content = await viewModel.generateSeriesEpisodeURLs(
            for: serie,
            categoryName: categoryName,
            format: selectedFormat
        )
        isGenerating = false
        
        copyToClipboard(content)
        dismiss()
    }
    
    #if os(macOS)
    private func generateAndExport() async {
        guard episodeDetails != nil else { return }
        
        isGenerating = true
        generatedContent = await viewModel.generateSeriesEpisodeURLs(
            for: serie,
            categoryName: categoryName,
            format: selectedFormat
        )
        isGenerating = false
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileExtension = selectedFormat == .json ? "json" : "txt"
        let seriesName = serie.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let filename = "episodes-\(seriesName)-\(timestamp).\(fileExtension)"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = selectedFormat == .json ? [.json] : [.plainText]
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try generatedContent.write(to: url, atomically: true, encoding: .utf8)
                    viewModel.log("✅ Episode URLs exported to: \(url.path)", type: .success)
                } catch {
                    viewModel.log("❌ Failed to export episode URLs: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    #endif
    
    private func copyToClipboard(_ content: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif
        
        let formatName = selectedFormat == .json ? "JSON" : "text"
        let totalEpisodes = episodeDetails?.episodes.values.reduce(0) { $0 + $1.count } ?? 0
        viewModel.log("📋 Copied \(formatName) episode URLs for \(serie.name) (\(totalEpisodes) episodes)", type: .success)
    }
}

// MARK: - Preview

struct SeriesEpisodeURLView_Previews: PreviewProvider {
    static var previews: some View {
        SeriesEpisodeURLView(
            serie: Serie(
                number: 1,
                name: "Sample Series",
                seriesId: 12345,
                cover: "",
                plot: "Sample plot",
                cast: "Sample cast",
                director: "Sample director",
                genre: "Drama",
                releaseDate: "2023",
                lastModified: "1234567890",
                rating: "8.5",
                rating5Based: 4.2,
                backdropPath: [],
                youtubeTrailer: "",
                episodeRunTime: "45",
                categoryId: "1"
            ),
            categoryName: "Drama",
            viewModel: DebugStreamingViewModel(
                movieService: MovieService(
                    profile: IPTVProfile(
                        name: "Preview",
                        baseURL: "http://preview.com",
                        username: "test",
                        password: "test"
                    )
                )
            )
        )
    }
}

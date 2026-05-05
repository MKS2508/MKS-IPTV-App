import SwiftUI
import IPTVCore

struct CategorySelectionView: View {
    @ObservedObject var viewModel: DebugStreamingViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedContentType: DebugStreamingView.ContentTab = .liveTV
    @State private var selectedCategoryIds: Set<String> = []
    @State private var selectedFormat: CategoryURLFormat = .text
    @State private var isGenerating = false
    @State private var generatedContent = ""
    @State private var showingPreview = false
    @State private var showingSeriesEpisodeView = false
    @State private var selectedSerie: Serie?
    @State private var selectedSerieCategoryName = ""
    
    #if os(macOS)
    @State private var showingSavePanel = false
    #endif
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                Divider()
                
                // Content selection
                contentSelectionSection
                
                Divider()
                
                // Category list
                categoryListSection
                
                Divider()
                
                // Series episode generator (only for series content type)
                if selectedContentType == .series {
                    seriesEpisodeSection
                    Divider()
                }
                
                // Format and actions
                actionsSection
                
                // Progress indicator
                if isGenerating {
                    ProgressView("Generating URLs...")
                        .padding()
                }
            }
            .navigationTitle("Copy Category URLs")
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
            if viewModel.movieCategories.isEmpty || viewModel.seriesCategories.isEmpty {
                await viewModel.loadAllCategories()
            }
        }
        .sheet(isPresented: $showingPreview) {
            previewView
        }
        .sheet(isPresented: $showingSeriesEpisodeView) {
            if let serie = selectedSerie {
                SeriesEpisodeURLView(
                    serie: serie,
                    categoryName: selectedSerieCategoryName,
                    viewModel: viewModel
                )
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select categories to copy URLs from")
                .font(.headline)
            
            Text("Choose content type, categories, and output format")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    // MARK: - Content Selection
    
    private var contentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content Type")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Picker("Content Type", selection: $selectedContentType) {
                ForEach(DebugStreamingView.ContentTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedContentType) { _, _ in
                selectedCategoryIds.removeAll()
            }
        }
        .padding()
    }
    
    // MARK: - Category List
    
    private var categoryListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories (\(availableCategories.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(selectedCategoryIds.isEmpty ? "Select All" : "Clear All") {
                    if selectedCategoryIds.isEmpty {
                        selectedCategoryIds = Set(availableCategories.map { $0.categoryId })
                    } else {
                        selectedCategoryIds.removeAll()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(availableCategories, id: \.categoryId) { category in
                        CategoryRow(
                            category: category,
                            isSelected: selectedCategoryIds.contains(category.categoryId),
                            contentType: selectedContentType
                        ) {
                            toggleCategory(category.categoryId)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(minHeight: 250, maxHeight: 400)
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
                .disabled(selectedCategoryIds.isEmpty || isGenerating)
                
                Button("Copy to Clipboard") {
                    Task {
                        await generateAndCopy()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCategoryIds.isEmpty || isGenerating)
                
                #if os(macOS)
                Button("Export to File") {
                    Task {
                        await generateAndExport()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(selectedCategoryIds.isEmpty || isGenerating)
                #endif
            }
            
            // Selection summary
            if !selectedCategoryIds.isEmpty {
                Text("\(selectedCategoryIds.count) categories selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Series Episode Section
    
    private var seriesEpisodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate Episode URLs")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("For series, you can generate individual episode URLs. Select a category to browse series.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !selectedCategoryIds.isEmpty {
                Button("Browse Series in Selected Categories") {
                    Task {
                        await loadAndShowSeriesBrowser()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("Select at least one series category to browse series")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
        )
        .padding(.horizontal)
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
            .navigationTitle("URL Preview")
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
    
    // MARK: - Helper Properties
    
    private var availableCategories: [any CategoryProtocol] {
        switch selectedContentType {
        case .liveTV:
            return viewModel.liveTVCategories
        case .movies:
            return viewModel.movieCategories
        case .series:
            return viewModel.seriesCategories
        case .mixed:
            return viewModel.movieCategories + viewModel.seriesCategories + viewModel.liveTVCategories
        }
    }
    
    // MARK: - Actions
    
    private func toggleCategory(_ categoryId: String) {
        if selectedCategoryIds.contains(categoryId) {
            selectedCategoryIds.remove(categoryId)
        } else {
            selectedCategoryIds.insert(categoryId)
        }
    }
    
    private func generateAndPreview() async {
        isGenerating = true
        generatedContent = await viewModel.generateCategoryURLs(
            contentType: selectedContentType,
            selectedCategoryIds: selectedCategoryIds,
            format: selectedFormat
        )
        isGenerating = false
        showingPreview = true
    }
    
    private func generateAndCopy() async {
        isGenerating = true
        let content = await viewModel.generateCategoryURLs(
            contentType: selectedContentType,
            selectedCategoryIds: selectedCategoryIds,
            format: selectedFormat
        )
        isGenerating = false
        
        copyToClipboard(content)
        dismiss()
    }
    
    #if os(macOS)
    private func generateAndExport() async {
        isGenerating = true
        generatedContent = await viewModel.generateCategoryURLs(
            contentType: selectedContentType,
            selectedCategoryIds: selectedCategoryIds,
            format: selectedFormat
        )
        isGenerating = false
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileExtension = selectedFormat == .json ? "json" : "txt"
        let filename = "category-urls-\(selectedContentType.rawValue.lowercased())-\(timestamp).\(fileExtension)"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = selectedFormat == .json ? [.json] : [.plainText]
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try generatedContent.write(to: url, atomically: true, encoding: .utf8)
                    viewModel.log("✅ URLs exported to: \(url.path)", type: .success)
                } catch {
                    viewModel.log("❌ Failed to export URLs: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    #endif
    
    private func loadAndShowSeriesBrowser() async {
        viewModel.log("🔍 Loading series from selected categories...", type: .info)
        
        do {
            // Load series from selected categories
            let allSeries = try await viewModel.movieService.fetchSeries()
            
            let filteredSeries = allSeries.filter { selectedCategoryIds.contains($0.categoryId) }
            
            // For demo purposes, take the first series
            if let firstSerie = filteredSeries.first {
                let categoryName = viewModel.seriesCategories
                    .first { $0.categoryId == firstSerie.categoryId }?.categoryName ?? "Unknown"
                
                selectedSerie = firstSerie
                selectedSerieCategoryName = categoryName
                showingSeriesEpisodeView = true
                
                viewModel.log("✅ Found \(filteredSeries.count) series, opening: \(firstSerie.name)", type: .success)
            } else {
                viewModel.log("❌ No series found in selected categories", type: .error)
            }
            
        } catch {
            viewModel.log("❌ Failed to load series: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func copyToClipboard(_ content: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif
        
        let formatName = selectedFormat == .json ? "JSON" : "text"
        let categoryCount = selectedCategoryIds.count
        viewModel.log("📋 Copied \(formatName) URLs for \(categoryCount) categories (\(selectedContentType.rawValue))", type: .success)
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let category: any CategoryProtocol
    let isSelected: Bool
    let contentType: DebugStreamingView.ContentTab
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.categoryName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("ID: \(category.categoryId)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Image(systemName: contentType.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Category Protocol

protocol CategoryProtocol {
    var categoryId: String { get }
    var categoryName: String { get }
}

extension LiveChannelCategory: CategoryProtocol {}
extension MovieCategory: CategoryProtocol {}
extension SeriesCategory: CategoryProtocol {}

// MARK: - Preview

struct CategorySelectionView_Previews: PreviewProvider {
    static var previews: some View {
        CategorySelectionView(
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

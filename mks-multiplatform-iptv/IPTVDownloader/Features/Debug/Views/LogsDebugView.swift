//
//  LogsDebugView.swift
//  mks-multiplatform-iptv
//
//  Real-time log viewer for TransmuxCore, PlayerLog, and CastLog.
//  Features: source tabs, level filtering, search, deduplication, copy.
//  macOS-only debug tool (wrapped in #if DEBUG at integration site).
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - ViewModel

@MainActor
@Observable
final class LogsDebugViewModel {

    // MARK: - State

    var selectedSource: LogSource = .transmux
    var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    var searchText: String = ""
    var isAutoScroll: Bool = true
    var isPolling: Bool = true

    private(set) var displayItems: [LogDisplayItem] = []
    private(set) var allEntries: [LogSource: [LogEntry]] = [:]
    private(set) var fileStats: [LogSource: LogFileStats] = [:]
    private(set) var lastRefresh: Date = Date()

    /// Filtered + deduplicated count for display.
    var filteredCount: Int { displayItems.count }

    /// Total raw entry count for current source.
    var totalCount: Int { allEntries[selectedSource]?.count ?? 0 }

    // MARK: - Internal

    private var pollingTask: Task<Void, Never>?
    private var lastFileOffsets: [LogSource: Int] = [:]
    private let maxEntries = 5000

    // MARK: - Lifecycle

    func startPolling() {
        guard pollingTask == nil else { return }
        // Initial full load
        loadAllSources()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isPolling, !Task.isCancelled else { continue }
                await self.pollForChanges()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Loading

    func loadAllSources() {
        for source in LogSource.allCases where source.isFileBased {
            loadSource(source)
        }
        setupRemoteLogReceiver()
        recomputeDisplay()
    }

    /// Subscribe to RemoteLogReceiver for the .remote source tab.
    private func setupRemoteLogReceiver() {
        #if os(macOS)
        let receiver = RemoteLogReceiver.shared
        receiver.onLogReceived = { [weak self] entry, device in
            guard let self else { return }
            // Parse the remote log entry into our LogEntry model
            let level: LogLevel = switch entry.level {
            case "error": .error
            case "warning": .warning
            case "debug": .debug
            default: .info
            }
            let logEntry = LogEntry(
                id: UUID(),
                timestamp: ISO8601DateFormatter().date(from: entry.timestamp) ?? Date(),
                level: level,
                tag: entry.tag,
                action: entry.message,
                fields: entry.fields ?? [:],
                rawLine: "📱[\(device.name)] [\(entry.tag)] \(entry.message)",
                source: .remote
            )
            var existing = self.allEntries[.remote] ?? []
            existing.append(logEntry)
            if existing.count > self.maxEntries {
                existing = Array(existing.suffix(self.maxEntries))
            }
            self.allEntries[.remote] = existing
            self.updateFileStats(.remote)
            if self.selectedSource == .remote {
                self.recomputeDisplay()
            }
        }
        if !receiver.isListening {
            receiver.start()
        }
        allEntries[.remote] = []
        #endif
    }

    func refresh() {
        lastFileOffsets.removeAll()
        allEntries.removeAll()
        loadAllSources()
    }

    func clearLog(source: LogSource) {
        if source.isFileBased {
            try? "".write(toFile: source.filePath, atomically: true, encoding: .utf8)
            lastFileOffsets[source] = 0
        }
        allEntries[source] = []
        recomputeDisplay()
    }

    // MARK: - Filtering

    func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
        recomputeDisplay()
    }

    func selectSource(_ source: LogSource) {
        selectedSource = source
        recomputeDisplay()
    }

    func updateSearch(_ text: String) {
        searchText = text
        recomputeDisplay()
    }

    // MARK: - Copy

    func copyAllFiltered() {
        let text = displayItems.map(\.copyText).joined(separator: "\n")
        copyToPasteboard(text)
    }

    func copyEntry(_ entry: LogEntry) {
        copyToPasteboard(entry.rawLine)
    }

    func copyGroup(_ group: CollapsedLogGroup) {
        let text = group.entries.map(\.rawLine).joined(separator: "\n")
        copyToPasteboard(text)
    }

    // MARK: - Export

    func exportText() -> String {
        let header = "=== MKS-IPTV Log Export — \(selectedSource.displayName) ===\n"
        let timestamp = "Exported: \(Date().formatted())\n"
        let stats = "Total entries: \(totalCount), Filtered: \(filteredCount)\n\n"
        let body = displayItems.map(\.copyText).joined(separator: "\n")
        return header + timestamp + stats + body
    }

    // MARK: - Private

    private func loadSource(_ source: LogSource) {
        guard source.isFileBased else { return }
        let path = source.filePath
        guard FileManager.default.fileExists(atPath: path) else {
            allEntries[source] = []
            updateFileStats(source)
            return
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            allEntries[source] = []
            updateFileStats(source)
            return
        }

        let entries = LogParser.parse(content: content, source: source)
        // Keep only the last maxEntries
        if entries.count > maxEntries {
            allEntries[source] = Array(entries.suffix(maxEntries))
        } else {
            allEntries[source] = entries
        }

        lastFileOffsets[source] = content.utf8.count
        updateFileStats(source)
    }

    private func pollForChanges() async {
        var changed = false

        for source in LogSource.allCases where source.isFileBased {
            let path = source.filePath
            guard FileManager.default.fileExists(atPath: path) else { continue }

            // Check file size to detect changes
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let fileSize = attrs[.size] as? Int else { continue }

            let lastOffset = lastFileOffsets[source] ?? 0
            guard fileSize > lastOffset else { continue }

            // Read only new content
            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            defer { try? handle.close() }

            handle.seek(toFileOffset: UInt64(lastOffset))
            guard let newData = try? handle.readToEnd(),
                  let newContent = String(data: newData, encoding: .utf8) else { continue }

            let newEntries = LogParser.parse(content: newContent, source: source)
            guard !newEntries.isEmpty else { continue }

            var existing = allEntries[source] ?? []
            existing.append(contentsOf: newEntries)

            // Trim if over limit
            if existing.count > maxEntries {
                existing = Array(existing.suffix(maxEntries))
            }

            allEntries[source] = existing
            lastFileOffsets[source] = fileSize
            updateFileStats(source)
            changed = true
        }

        if changed {
            await MainActor.run {
                lastRefresh = Date()
                recomputeDisplay()
            }
        }
    }

    private func recomputeDisplay() {
        let entries = allEntries[selectedSource] ?? []

        // Apply level filter
        var filtered = entries.filter { selectedLevels.contains($0.level) }

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { entry in
                entry.action.lowercased().contains(query) ||
                entry.tag.lowercased().contains(query) ||
                entry.rawLine.lowercased().contains(query)
            }
        }

        // Deduplicate
        displayItems = LogDeduplicator.deduplicate(filtered)
    }

    private func updateFileStats(_ source: LogSource) {
        let path = source.filePath
        let exists = FileManager.default.fileExists(atPath: path)
        var size: Int64 = 0
        var lineCount = 0

        if exists {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                size = attrs[.size] as? Int64 ?? 0
            }
            lineCount = allEntries[source]?.count ?? 0
        }

        fileStats[source] = LogFileStats(
            source: source,
            fileSize: size,
            lineCount: lineCount,
            exists: exists
        )
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Main View

struct LogsDebugView: View {
    @State private var viewModel = LogsDebugViewModel()
    @State private var scrollPosition: UUID?
    @State private var expandedGroups: Set<UUID> = []
    @State private var showExportSheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logContent
        }
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
        .onChange(of: viewModel.displayItems.count) { _, _ in
            if viewModel.isAutoScroll, let lastID = viewModel.displayItems.last?.id {
                scrollPosition = lastID
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            // Row 1: Source picker + actions
            HStack(spacing: 12) {
                sourcePicker
                Spacer()
                statsBar
                actionButtons
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Row 2: Level filter + search
            HStack(spacing: 8) {
                levelFilter
                Spacer()
                searchField
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    // MARK: - Source Picker

    private var sourcePicker: some View {
        HStack(spacing: 4) {
            ForEach(LogSource.allCases) { source in
                SourceTab(
                    source: source,
                    isSelected: viewModel.selectedSource == source,
                    entryCount: viewModel.allEntries[source]?.count ?? 0
                )
                .onTapGesture { viewModel.selectSource(source) }
            }
        }
    }

    // MARK: - Level Filter

    private var levelFilter: some View {
        HStack(spacing: 4) {
            ForEach(LogLevel.allCases) { level in
                LevelFilterBadge(
                    level: level,
                    isSelected: viewModel.selectedLevels.contains(level)
                )
                .onTapGesture { viewModel.toggleLevel(level) }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search logs...", text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.updateSearch($0) }
            ))
            .textFieldStyle(.plain)
            .font(.caption)
            .frame(maxWidth: 200)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.updateSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 8) {
            if let stats = viewModel.fileStats[viewModel.selectedSource] {
                Text("\(viewModel.filteredCount)/\(viewModel.totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(stats.formattedSize)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // Polling indicator
            Circle()
                .fill(viewModel.isPolling ? .green : .gray)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.isAutoScroll.toggle()
            } label: {
                Image(systemName: viewModel.isAutoScroll ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isAutoScroll ? "Auto-scroll ON" : "Auto-scroll OFF")

            Button {
                viewModel.isPolling.toggle()
            } label: {
                Image(systemName: viewModel.isPolling ? "pause.circle" : "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isPolling ? "Pause polling" : "Resume polling")

            Button {
                viewModel.copyAllFiltered()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy all filtered logs")

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Reload logs")

            Menu {
                Button("Clear \(viewModel.selectedSource.displayName) log") {
                    viewModel.clearLog(source: viewModel.selectedSource)
                }
                Button("Clear all logs") {
                    for source in LogSource.allCases {
                        viewModel.clearLog(source: source)
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Clear logs")
        }
    }

    // MARK: - Log Content

    private var logContent: some View {
        Group {
            if viewModel.displayItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List(viewModel.displayItems) { item in
                        logItemRow(item)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: scrollPosition) { _, newID in
                        if let newID {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No log entries")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Logs will appear here when \(viewModel.selectedSource.displayName) writes to its log file.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Text(viewModel.selectedSource.filePath)
                .font(.caption2.monospaced())
                .foregroundStyle(.quaternary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Item Row

    @ViewBuilder
    private func logItemRow(_ item: LogDisplayItem) -> some View {
        switch item {
        case .single(let entry):
            LogEntryRow(entry: entry) {
                viewModel.copyEntry(entry)
            }
        case .group(let group):
            CollapsedLogGroupRow(
                group: group,
                isExpanded: expandedGroups.contains(group.id),
                onToggle: {
                    if expandedGroups.contains(group.id) {
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                },
                onCopyGroup: { viewModel.copyGroup(group) },
                onCopyEntry: { viewModel.copyEntry($0) }
            )
        }
    }
}

// MARK: - Source Tab

private struct SourceTab: View {
    let source: LogSource
    let isSelected: Bool
    let entryCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.iconName)
                .font(.caption2)
            Text(source.displayName)
                .font(.caption.weight(.medium))
            if entryCount > 0 {
                Text("\(entryCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? .white.opacity(0.2) : Color.secondary.opacity(0.15))
                    )
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? source.color : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Level Filter Badge

private struct LevelFilterBadge: View {
    let level: LogLevel
    let isSelected: Bool

    var body: some View {
        Text(level.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? .white : level.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? level.color : level.color.opacity(0.15))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Timestamp
            Text(entry.formattedTimestamp)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(entry.level.color, in: RoundedRectangle(cornerRadius: 3))

            // Tag badge
            Text(entry.tag)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))

            // Action + fields
            Text(entry.action)
                .fontWeight(.medium)

            if !entry.fields.isEmpty {
                Text(entry.fieldsDescription)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            // Copy button (visible on hover)
            if isHovered {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
    }

    private var rowBackground: some ShapeStyle {
        if isHovered {
            return AnyShapeStyle(Color.secondary.opacity(0.08))
        }
        switch entry.level {
        case .error:
            return AnyShapeStyle(Color.red.opacity(0.06))
        case .warning:
            return AnyShapeStyle(Color.orange.opacity(0.04))
        default:
            return AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - Collapsed Group Row

private struct CollapsedLogGroupRow: View {
    let group: CollapsedLogGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopyGroup: () -> Void
    let onCopyEntry: (LogEntry) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                // Timestamp
                Text(group.sampleEntry.formattedTimestamp)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                // Level badge
                Text(group.level.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(group.level.color, in: RoundedRectangle(cornerRadius: 3))

                // Pattern + count
                Text(group.pattern)
                    .fontWeight(.medium)

                Text("\u{00D7}\(group.count)")
                    .foregroundStyle(.orange)
                    .fontWeight(.semibold)

                // Duration
                if group.duration > 0 {
                    Text("(\(group.formattedDuration))")
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                // Copy group button
                if isHovered {
                    Button(action: onCopyGroup) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(Color.secondary.opacity(isHovered ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { isHovered = $0 }

            // Expanded entries
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.entries) { entry in
                        LogEntryRow(entry: entry) {
                            onCopyEntry(entry)
                        }
                        .padding(.leading, 16)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("LogsDebugView") {
    LogsDebugView()
        .frame(width: 900, height: 600)
}
#endif

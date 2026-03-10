//
//  CacheDebugView.swift
//  mks-multiplatform-iptv
//
//  Debug view showing cache statistics, entry freshness, and management controls.
//  Uses CacheStats from CacheManager for type-aware TTL reporting.
//

import SwiftUI

struct CacheDebugView: View {
    @State private var stats: CacheStats?
    @State private var isRefreshing = false
    @State private var showClearAllConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                if let stats {
                    summarySection(stats)
                    typeBreakdownSection(stats)
                    ttlReferenceSection
                    entriesSection(stats)
                } else {
                    ProgressView("Loading cache stats...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .task { refreshStats() }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
        .navigationTitle("Cache Inspector")
        .alert("Clear All Cache?", isPresented: $showClearAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                CacheManager.shared.clearCache()
                // Wait a beat for the async barrier write to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    refreshStats()
                }
            }
        } message: {
            Text("This will remove all cached data. The app will re-fetch everything from the server on next use.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cache Inspector")
                    .font(.title2.weight(.semibold))
                Text("SWR disk cache with type-aware TTLs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                refreshStats()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(.easeInOut(duration: 0.5), value: isRefreshing)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Summary

    private func summarySection(_ stats: CacheStats) -> some View {
        HStack(spacing: 16) {
            StatCard(title: "Total Size", value: stats.formattedTotalSize, icon: "internaldrive")
            StatCard(title: "Entries", value: "\(stats.entryCount)", icon: "doc.on.doc")
            StatCard(
                title: "Fresh",
                value: "\(stats.entries.filter { !$0.isStale && !$0.isExpired }.count)",
                icon: "checkmark.circle",
                tint: .green
            )
            StatCard(
                title: "Stale",
                value: "\(stats.entries.filter { $0.isStale && !$0.isExpired }.count)",
                icon: "clock.badge.exclamationmark",
                tint: .orange
            )
        }
    }

    // MARK: - Type Breakdown

    private func typeBreakdownSection(_ stats: CacheStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Type")
                .font(.headline)

            ForEach(CacheTTL.allCases, id: \.rawValue) { type in
                let count = stats.count(for: type)
                if count > 0 {
                    typeRow(type: type, stats: stats)
                }
            }

            // Unclassified entries
            let unclassified = stats.entries.filter { $0.ttlType == nil }
            if !unclassified.isEmpty {
                HStack {
                    Label("Other", systemImage: "questionmark.circle")
                        .font(.subheadline)
                    Spacer()
                    Text("\(unclassified.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func typeRow(type: CacheTTL, stats: CacheStats) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForType(type))
                .foregroundStyle(colorForType(type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.subheadline.weight(.medium))
                Text("Fresh \(formatTTL(type.freshTTL)) / Stale \(formatTTL(type.staleTTL))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Fresh / Stale / Expired counts
            HStack(spacing: 6) {
                let fresh = stats.freshCount(for: type)
                let stale = stats.staleCount(for: type)
                let expired = stats.expiredCount(for: type)

                if fresh > 0 {
                    CacheBadge(count: fresh, color: .green, label: "fresh")
                }
                if stale > 0 {
                    CacheBadge(count: stale, color: .orange, label: "stale")
                }
                if expired > 0 {
                    CacheBadge(count: expired, color: .red, label: "expired")
                }
            }

            Text(ByteCountFormatter.string(fromByteCount: stats.sizeBytes(for: type), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Button {
                CacheManager.shared.clearCache(type: type)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    refreshStats()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - TTL Reference

    private var ttlReferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TTL Reference")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Type").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Fresh").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Stale Max").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }

                ForEach(CacheTTL.allCases, id: \.rawValue) { type in
                    GridRow {
                        Text(type.displayName).font(.caption)
                        Text(formatTTL(type.freshTTL)).font(.caption).foregroundStyle(.green)
                        Text(formatTTL(type.staleTTL)).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Entries List

    private func entriesSection(_ stats: CacheStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All Entries (\(stats.entryCount))")
                    .font(.headline)
                Spacer()

                Button("Clear Expired") {
                    CacheManager.shared.clearExpiredCache()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        refreshStats()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear All", role: .destructive) {
                    showClearAllConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            LazyVStack(spacing: 4) {
                ForEach(stats.entries) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    private func entryRow(_ entry: CacheStats.Entry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(freshnessColor(entry))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.key)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                    Text(formatAge(entry.age))
                    if let type = entry.ttlType {
                        Text(type.displayName)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(freshnessLabel(entry))
                .font(.caption2.weight(.medium))
                .foregroundStyle(freshnessColor(entry))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(freshnessColor(entry).opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func refreshStats() {
        isRefreshing = true
        stats = CacheManager.shared.getCacheStats()
        isRefreshing = false
    }

    private func freshnessColor(_ entry: CacheStats.Entry) -> Color {
        if entry.isExpired { return .red }
        if entry.isStale { return .orange }
        return .green
    }

    private func freshnessLabel(_ entry: CacheStats.Entry) -> String {
        if entry.isExpired { return "Expired" }
        if entry.isStale { return "Stale" }
        return "Fresh"
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return String(format: "%.1fh ago", seconds / 3600) }
        return String(format: "%.1fd ago", seconds / 86400)
    }

    private func formatTTL(_ seconds: TimeInterval) -> String {
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    private func iconForType(_ type: CacheTTL) -> String {
        switch type {
        case .mediaList:    return "list.bullet"
        case .mediaDetail:  return "doc.text"
        case .metadata:     return "tag"
        case .epg:          return "calendar"
        case .matchTable:   return "arrow.left.arrow.right"
        case .categories:   return "folder"
        case .liveChannels: return "tv"
        }
    }

    private func colorForType(_ type: CacheTTL) -> Color {
        switch type {
        case .mediaList:    return .blue
        case .mediaDetail:  return .purple
        case .metadata:     return .orange
        case .epg:          return .green
        case .matchTable:   return .cyan
        case .categories:   return .yellow
        case .liveChannels: return .red
        }
    }
}

// MARK: - Subviews

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CacheBadge: View {
    let count: Int
    let color: Color
    let label: String

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel("\(count) \(label)")
    }
}

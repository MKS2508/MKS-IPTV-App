//
//  DetailInfoPanel.swift
//  mks-multiplataforma-tvos-iptv
//
//  Reusable info panel for detail views.
//  Glass pills, expandable synopsis, action buttons, dismiss via button.
//

import SwiftUI

struct DetailInfoPanel: View {
    let title: String
    let metadata: [MetadataItem]
    let synopsis: String?
    let actions: [PanelAction]
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var panelOffset: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            // Header with drag indicator + close button
            panelHeader

            VStack(alignment: .leading, spacing: 20) {
                headerSection
                metadataRow
                synopsisSection
                actionsRow
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .offset(y: panelOffset)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                panelOffset = 0
            }
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack {
            Spacer()

            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 48, height: 6)

                Text("Info")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    panelOffset = 500
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Content Sections

    private var headerSection: some View {
        Text(title)
            .font(.system(size: 52, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            ForEach(metadata) { item in
                GlassPill(text: item.text)
            }
        }
    }

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(synopsis ?? "")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let synopsis, synopsis.count > 150 {
                Button(isExpanded ? "Show less" : "Read more") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 16) {
            ForEach(actions) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: PanelAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: 8) {
                Image(systemName: action.icon)
                Text(action.label)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(GlassProminentCompatButtonStyle())
    }

    private var panelBackground: some View {
        Group {
            if #available(tvOS 26, *) {
                Rectangle()
                    .fill(.black.opacity(0.7))
                    .glassEffect(.regular.tint(.black.opacity(0.1)), in: .rect(cornerRadius: 0))
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Supporting Types

struct MetadataItem: Identifiable {
    let id = UUID()
    let text: String
    var icon: String? = nil
}

struct PanelAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let action: () -> Void
}

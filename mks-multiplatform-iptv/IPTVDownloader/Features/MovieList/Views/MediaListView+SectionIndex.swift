//
//  MediaListView+SectionIndex.swift
//  mks-multiplatform-iptv
//
//  Section index component for MediaListView
//

import SwiftUI

extension MediaListView {
    // MARK: - Section Index View
    
    @ViewBuilder
    var sectionIndexView: some View {
        if let grouped = groupedItems, grouped.count > 5 {
            VStack(spacing: 2) {
                ForEach(Array(zip(grouped.indices, grouped)), id: \.1.key) { index, section in
                    SectionIndexButton(
                        title: indexTitles[index],
                        action: {
                            scrollToSection(section.key)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.trailing, 8)
        }
    }
    
    // Helper method to trigger scroll
    func scrollToSection(_ sectionKey: String) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.scrollToSectionSubject.send(sectionKey)
        #endif
    }
}

// MARK: - Section Index Button Component

struct SectionIndexButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.primary)
                .frame(width: 24, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header Component

struct MediaSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            .regularMaterial.opacity(0.8),
            in: Rectangle()
        )
    }
}

//
//  HomeView.swift
//  mks-multiplatform-iptv
//
//  Netflix-style Home screen composing hero banner, EPG sections,
//  recently added content, category spotlights, and live TV categories
//

import SwiftUI

struct HomeView: View {
    let homeViewModel: HomeViewModel
    @Binding var selectedView: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(homeViewModel.sections) { section in
                    sectionView(for: section)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.black)
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section.type {
        case .heroBanner(let item):
            HeroBannerView(item: item, selectedView: $selectedView)

        case .nowOnTV(let channels):
            sectionHeader(title: section.title, icon: section.iconName)
            NowOnTVCarousel(channels: channels, selectedView: $selectedView)

        case .comingUpNext(let programmes):
            sectionHeader(title: section.title, icon: section.iconName)
            ComingUpNextTimeline(programmes: programmes)

        case .mediaCarousel(let items):
            sectionHeader(title: section.title, icon: section.iconName)
            HomeMediaCarousel(items: items, selectedView: $selectedView)

        case .liveTVCategory(let channels, _):
            sectionHeader(title: section.title, icon: section.iconName)
            liveTVCarousel(channels: channels)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String?) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.accent)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Live TV Category Carousel

    private func liveTVCarousel(channels: [LiveChannel]) -> some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(channels) { channel in
                        Button {
                            selectedView = NavigationDestination.liveChannels.rawValue
                        } label: {
                            liveChannelMiniCard(channel: channel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func liveChannelMiniCard(channel: LiveChannel) -> some View {
        VStack(spacing: 8) {
            // Channel icon
            if let iconURL = channel.streamIcon, let url = URL(string: iconURL) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        channelIconPlaceholder
                    }
                }
            } else {
                channelIconPlaceholder
            }

            Text(channel.name)
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .padding(10)
        .frame(width: 100, height: 100)
        .background(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(Color.white.opacity(0.04))
        )
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
    }

    private var channelIconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(AppColors.surface)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "tv")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }
}

//
//  MediaListView+StateViews.swift
//  mks-multiplatform-iptv
//
//  State views (loading, error, empty) for MediaListView with Liquid Glass styling
//

import SwiftUI

extension MediaListView {
    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: 24) {
            if LiquidGlassAvailability.isAvailable {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                    .glassEffect(.regular, in: Circle())
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            Text("Loading \(navigationPrompt)...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Error View

    func errorView(error: Error) -> some View {
        ErrorView(error: error, retryAction: {
            Task { await viewModel.refreshMedia(contentType: contentTypeFilter) }
        })
        .frame(maxHeight: .infinity)
    }

    // MARK: - Empty State View

    var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: contentTypeFilter == .series ? "tv.slash" : "film.slash")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.7))
                .ifAvailable { view in
                    view.symbolEffect(.pulse)
                }

            Text("No \(navigationTitle)")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            if !effectiveSearchText.isEmpty || !effectiveSelectedCategories.isEmpty {
                Text("Try adjusting your filters")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)

                Button(action: {
                    searchText = ""
                    selectedCategories.removeAll()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Clear Filters")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.appGlassProminent)
                .padding(.top, 8)
            } else {
                Text("Your \(navigationPrompt) will appear here")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loading Detail Overlay

    var loadingDetailOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if LiquidGlassAvailability.isAvailable {
                    ProgressView()
                        .scaleEffect(1.8)
                        .tint(.white)
                        .glassEffect(.regular, in: Circle())
                } else {
                    ProgressView()
                        .scaleEffect(1.8)
                        .tint(.white)
                }

                Text("Loading details...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: AppGlass.cornerRadiusLarge)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }

    // MARK: - Error Detail View

    var errorDetailView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text("Failed to load details")
                .font(.title3.bold())
                .foregroundColor(.white)

            Text("There was a problem loading the content you requested.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Dismiss") {
                dismissMediaDetail()
            }
            .buttonStyle(.appGlassProminent)
        }
        .padding(40)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusLarge)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
    }
}

// MARK: - View Extension for Availability

private extension View {
    /// Apply modifier only if iOS 26+/macOS 26+ is available
    @ViewBuilder
    func ifAvailable<Content: View>(@ViewBuilder transform: (Self) -> Content) -> some View {
        if LiquidGlassAvailability.isAvailable {
            transform(self)
        } else {
            self
        }
    }
}

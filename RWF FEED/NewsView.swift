//
//  NewsView.swift
//  RWF FEED
//
//  General WoW retail news from Wowhead's public RSS feed — patch notes, tuning changes,
//  hotfixes — the kind of thing that explains why a guild's pace suddenly changed mid-race.
//

import SwiftUI

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()
    @State private var showingSettings = false
    /// See FeedView's isActive doc comment — ContentView keeps every visited tab mounted, so
    /// polling has to be paused/resumed off this instead of .onDisappear (which never fires).
    var isActive: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(
                    title: "News", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated,
                    creditLabel: "News by Wowhead", creditURL: URL(string: "https://www.wowhead.com/news")!,
                    creditMark: "WowheadMark"
                ) {
                    showingSettings = true
                }

                Group {
                    if viewModel.articles.isEmpty && viewModel.isLoading {
                        ProgressView("Loading news…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.articles.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Theme.cardGap) {
                                ForEach(viewModel.articles) { article in
                                    NewsArticleRow(article: article)
                                }
                            }
                            .padding(.horizontal, Theme.screenEdgeMargin)
                            .padding(.vertical, Theme.cardGap / 2)
                        }
                        .scrollContentBackground(.hidden)
                        .refreshable { await viewModel.refresh() }
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
        .task {
            if isActive { viewModel.startPolling() }
        }
        .onChange(of: isActive) { _, active in
            if active { viewModel.startPolling() } else { viewModel.stopPolling() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct NewsArticleRow: View {
    let article: WowheadArticle

    var body: some View {
        Link(destination: article.link) {
            VStack(alignment: .leading, spacing: Theme.cardRowGap) {
                if let imageURL = article.imageURL {
                    // GeometryReader pins the image to a concrete, finite width — a bare
                    // .frame(maxWidth: .infinity) still lets .scaledToFill() propose an
                    // unbounded width for a very wide source image, which balloons the whole
                    // card (and row) out past the screen instead of just the image getting
                    // clipped to it.
                    GeometryReader { geo in
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                // .scaledToFill() (not an overridden .aspectRatio) preserves
                                // the image's own proportions and crops to the frame, rather
                                // than stretching the pixels to force a 16:9 shape.
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Text(article.title)
                    .font(Theme.authorName)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)

                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(Theme.postBody)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Text(RelativeTime.short(from: article.publishedAt))
                    .font(Theme.timestamp)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.cardPadding)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NewsView()
}

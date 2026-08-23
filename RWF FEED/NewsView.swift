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
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
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
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            // .scaledToFill() (not an overridden .aspectRatio) preserves the
                            // image's own proportions and crops to the frame below, rather than
                            // stretching the pixels to force a 16:9 shape.
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .clipped()
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

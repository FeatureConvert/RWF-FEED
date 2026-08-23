//
//  FeedView.swift
//  RWF FEED
//

import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Venomous Abyss", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated, creditLabel: "Feed by Raider.IO") {
                    showingSettings = true
                }

                Group {
                    if viewModel.posts.isEmpty && viewModel.isLoading {
                        ProgressView("Loading feed…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.posts.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else {
                        // A plain ScrollView instead of List: rows contain WKWebView embeds
                        // that resize themselves asynchronously once their content loads,
                        // and List's UICollectionView-backed layout can't tolerate a cell
                        // changing height mid-layout-pass — it aborts with an internal
                        // consistency assertion. A ScrollView/LazyVStack has no such
                        // constraint.
                        ScrollView {
                            LazyVStack(spacing: Theme.cardGap) {
                                ForEach(viewModel.posts) { post in
                                    FeedPostRow(post: post)
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

/// Fixed title bar matching the spec's "Screen / nav title" role — left-aligned, 20pt
/// medium, sitting above the scroll content rather than in system nav-bar chrome.
struct ScreenHeader: View {
    let title: String
    var isLoading: Bool = false
    var lastUpdated: Date? = nil
    /// "Feed by Raider.IO" on the Feed tab (it's literally their feed); every other
    /// raider.io-backed tab shows the more accurate "Data by Raider.IO" since they're derived
    /// views, not the feed. The News tab overrides all three credit params for Wowhead instead.
    var creditLabel: String = "Data by Raider.IO"
    var creditURL: URL = URL(string: "https://raider.io")!
    /// Asset catalog image name for the small mark next to the credit text. Nil omits the
    /// mark entirely — used for News since Wowhead's logo hasn't been sourced/vetted the way
    /// Raider.IO's was.
    var creditMark: String? = "RaiderIOMark"
    /// Shows a gear button that calls this when tapped — used on the Feed tab to open
    /// Settings. Omitted (nil) everywhere else.
    var onSettingsTapped: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(Theme.screenTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Link(destination: creditURL) {
                        HStack(spacing: 3) {
                            if let creditMark {
                                Image(creditMark)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                            }
                            Text(creditLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                if let lastUpdated {
                    TimelineView(.periodic(from: lastUpdated, by: 5)) { context in
                        Text("Updated \(RelativeTime.short(from: lastUpdated, to: context.date))")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if isLoading {
                ProgressView()
            }
            if let onSettingsTapped {
                Button(action: onSettingsTapped) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, Theme.screenEdgeMargin)
        .padding(.bottom, 14)
    }
}

struct FeedPostRow: View {
    let post: FeedPost

    private var blocks: [PostContentBlock] { PostContent.parseBlocks(from: post.content ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardRowGap) {
            HStack(spacing: 6) {
                Text(post.author ?? "Raider.IO")
                    .font(Theme.authorName)
                    .foregroundStyle(Theme.textPrimary)
                if post.isPriority {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.star)
                }
                Spacer()
                Text(RelativeTime.short(from: post.publishedAt))
                    .font(Theme.timestamp)
                    .foregroundStyle(Theme.textSecondary)
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let attributed):
                    Text(attributed)
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.accentText)
                case .image(let url):
                    PostImageView(url: url)
                case .embed(let info):
                    EmbedBlockView(info: info)
                }
            }

            if !post.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(post.tags) { tag in
                        Text(tag.name)
                            .font(Theme.tagLabel)
                            .tracking(Theme.tagLabelTracking)
                            .foregroundStyle(Theme.tagText)
                            .padding(.horizontal, Theme.tagHPadding)
                            .padding(.vertical, Theme.tagVPadding)
                            .background(Theme.tagFill, in: RoundedRectangle(cornerRadius: Theme.tagCornerRadius, style: .continuous))
                    }
                }
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }
}

struct PostImageView: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else if phase.error != nil {
                EmptyView()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    FeedView()
}

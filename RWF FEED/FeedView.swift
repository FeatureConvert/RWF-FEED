//
//  FeedView.swift
//  RWF FEED
//

import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showingSettings = false
    /// Whether this is the currently-selected tab. ContentView keeps every visited tab
    /// mounted (just visually swapped) rather than tearing it down, so `.onDisappear` never
    /// fires — polling has to be paused/resumed off this instead, or every visited tab polls
    /// forever in the background regardless of which one is actually on screen.
    var isActive: Bool = true

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
                    } else if viewModel.posts.isEmpty {
                        ScrollView {
                            ContentUnavailableView(
                                "No Coverage Yet",
                                systemImage: "bolt",
                                description: Text("Live coverage posts will appear here once the race is underway.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 400)
                        }
                        .refreshable { await viewModel.refresh() }
                    } else {
                        // A plain ScrollView instead of List: rows contain WKWebView embeds
                        // that resize themselves asynchronously once their content loads,
                        // and List's UICollectionView-backed layout can't tolerate a cell
                        // changing height mid-layout-pass — it aborts with an internal
                        // consistency assertion. A ScrollView/LazyVStack has no such
                        // constraint.
                        ScrollView {
                            // HStack + Spacers rather than a bare .frame(maxWidth:).frame(maxWidth: .infinity)
                            // chain — the latter left the column pinned to the leading edge and
                            // narrower than its own cap inside a ScrollView, since nested frame
                            // modifiers depend on an unambiguous width proposal from the parent
                            // that a ScrollView's content slot doesn't reliably give. An HStack
                            // gives the capped column a concrete width to fill, and two
                            // symmetric Spacers guarantee centering regardless.
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                LazyVStack(spacing: Theme.cardGap) {
                                    ForEach(viewModel.posts) { post in
                                        FeedPostRow(post: post)
                                    }
                                }
                                .padding(.horizontal, Theme.screenEdgeMargin)
                                .padding(.vertical, Theme.cardGap / 2)
                                .frame(maxWidth: 700)
                                Spacer(minLength: 0)
                            }
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
                                    // Decorative mark next to the credit text — the Link's
                                    // label already reads fine from creditLabel alone.
                                    .accessibilityHidden(true)
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
                .accessibilityLabel("Settings")
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, Theme.screenEdgeMargin)
        .padding(.bottom, 14)
    }
}

struct FeedPostRow: View {
    let post: FeedPost
    /// Parsed once per post.id via .task below rather than recomputed on every render —
    /// PostContent.parseBlocks() → HTMLContent.attributedString() runs NSAttributedString's
    /// HTML importer, which is main-thread-only and not cheap; as a plain computed property it
    /// re-ran on every SwiftUI re-render (including every 30s poll, since that replaces the
    /// whole `posts` array). .task(id: post.id) keeps this on the main thread — this codebase
    /// already tried moving HTML parsing off it once and had to revert the whole change, so
    /// this is caching, not threading.
    @State private var blocks: [PostContentBlock] = []

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
                        .accessibilityLabel("Priority post")
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

            // Only "guild" tags (e.g. "Liquid", "Echo") have clean, human-presentable names —
            // confirmed live against the feed API, the other categories are either raw internal
            // slugs ("day-6", name === slug, not reformatted anywhere upstream) or messy
            // free-form text (stray trailing commas, lowercase fragments like "wish"/"lost").
            let presentableTags = post.tags.filter { $0.category == "guild" }
            if !presentableTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(presentableTags) { tag in
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
        .task(id: post.id) {
            blocks = PostContent.parseBlocks(from: post.content ?? "")
        }
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

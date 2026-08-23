//
//  KillFeedView.swift
//  RWF FEED
//
//  A chronological log of every boss kill across every guild — not just the narrative
//  blog posts in the main feed, and not just the current per-guild standing in Tracker.
//

import SwiftUI

struct KillFeedView: View {
    @StateObject private var viewModel = KillFeedViewModel()
    @State private var showingSettings = false
    /// See FeedView's isActive doc comment — ContentView keeps every visited tab mounted, so
    /// polling has to be paused/resumed off this instead of .onDisappear (which never fires).
    var isActive: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Venomous Abyss", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated) {
                    showingSettings = true
                }

                Group {
                    if viewModel.events.isEmpty && viewModel.isLoading {
                        ProgressView("Loading kill feed…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.events.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else if viewModel.events.isEmpty {
                        List {
                            ContentUnavailableView(
                                "No Kills Yet",
                                systemImage: "checkmark.seal",
                                description: Text("Boss kills will show up here as guilds land them.")
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await viewModel.refresh() }
                    } else {
                        List(Array(viewModel.events.enumerated()), id: \.element.id) { index, event in
                            KillFeedRow(event: event, isLast: index == viewModel.events.count - 1)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                        .listStyle(.plain)
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

struct KillFeedRow: View {
    let event: KillFeedEvent
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                GuildAvatar(guild: event.guild)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(event.guild.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("killed")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 6) {
                        AsyncImage(url: event.boss.fullIconURL) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                        Text(event.boss.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if event.rank == 1 {
                        WorldFirstBadge()
                    } else {
                        Text(event.rankLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(RelativeTime.short(from: event.defeatedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, Theme.trackerRowVPadding)
            .padding(.horizontal, Theme.trackerRowHPadding)

            if !isLast {
                FadingDivider()
            }
        }
    }
}

#Preview {
    KillFeedView()
}

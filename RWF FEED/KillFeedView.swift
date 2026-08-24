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
                    if viewModel.groups.isEmpty && viewModel.isLoading {
                        ProgressView("Loading kill feed…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.groups.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else if viewModel.groups.isEmpty {
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
                        List {
                            ForEach(viewModel.groups) { group in
                                Section {
                                    ForEach(Array(group.kills.enumerated()), id: \.element.id) { index, event in
                                        KillFeedRow(event: event, isLast: index == group.kills.count - 1)
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    }
                                } header: {
                                    BossGroupHeader(boss: group.boss)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .listSectionSpacing(.compact)
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

struct BossGroupHeader: View {
    let boss: Encounter

    var body: some View {
        HStack(spacing: 6) {
            AsyncImage(url: boss.fullIconURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.clear
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(boss.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .textCase(nil)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .padding(.horizontal, Theme.trackerRowHPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }
}

struct KillFeedRow: View {
    let event: KillFeedEvent
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                GuildAvatar(guild: event.guild)

                Text(event.guild.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

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
            .padding(.vertical, 8)
            .padding(.leading, Theme.trackerRowHPadding + 36)
            .padding(.trailing, Theme.trackerRowHPadding)

            if !isLast {
                FadingDivider()
                    .padding(.leading, Theme.trackerRowHPadding + 36)
            }
        }
    }
}

#Preview {
    KillFeedView()
}

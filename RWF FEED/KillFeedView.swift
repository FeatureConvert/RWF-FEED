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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bosses collapsed by the user — absent means expanded, so a newly-appearing boss (one
    /// nobody's collapsed yet) always starts expanded rather than needing to be in some
    /// explicit "expanded" set.
    @State private var collapsedBossIDs: Set<Int> = []
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
                        // Plain ScrollView + LazyVStack rather than List's Section(header:) —
                        // gives BossGroupHeader below a normal SwiftUI view to attach its tap
                        // gesture to, without going through List's UIKit table section-header
                        // wrapping.
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(viewModel.groups) { group in
                                    let isExpanded = !collapsedBossIDs.contains(group.boss.id)
                                    VStack(spacing: 0) {
                                        BossGroupHeader(boss: group.boss, isExpanded: isExpanded) {
                                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                                if isExpanded {
                                                    collapsedBossIDs.insert(group.boss.id)
                                                } else {
                                                    collapsedBossIDs.remove(group.boss.id)
                                                }
                                            }
                                        }
                                        if isExpanded {
                                            ForEach(Array(group.kills.enumerated()), id: \.element.id) { index, event in
                                                KillFeedRow(event: event, isLast: index == group.kills.count - 1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
    let isExpanded: Bool
    let onToggle: () -> Void

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

            Spacer()

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.trackerRowHPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        // A plain onTapGesture (not a Button) on a row of otherwise-separate icon/text/
        // chevron children — without this, VoiceOver exposes the boss icon, name, and
        // chevron as three unrelated stops and none of them expose the collapse/expand
        // action. Collapsing to one element with an explicit button trait and value makes
        // it behave like a real disclosure control under VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(boss.name)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onToggle()
        }
    }
}

struct KillFeedRow: View {
    let event: KillFeedEvent
    let isLast: Bool

    private var accessibilitySummary: String {
        let rank = event.rank == 1 ? "World First" : event.rankLabel
        return "\(event.guild.displayName), \(rank), \(RelativeTime.short(from: event.defeatedAt))"
    }

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

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

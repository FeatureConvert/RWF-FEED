//
//  TrackerView.swift
//  RWF FEED
//

import SwiftUI

struct TrackerView: View {
    @StateObject private var viewModel = TrackerViewModel()
    @ObservedObject private var pinnedGuilds = PinnedGuilds.shared
    @State private var showingSettings = false
    /// See FeedView's isActive doc comment — ContentView keeps every visited tab mounted, so
    /// polling has to be paused/resumed off this instead of .onDisappear (which never fires).
    var isActive: Bool = true

    /// Capped to the top 25 the same way the whole list used to be, but a pinned guild always
    /// shows regardless of rank (that's the point of pinning one outside the visible range) —
    /// so it's excluded here and shown in its own section instead, not duplicated.
    private var pinnedStandings: [GuildStanding] {
        viewModel.standings.filter { pinnedGuilds.isPinned($0.guild.id) }
    }

    private var otherStandings: [GuildStanding] {
        Array(viewModel.standings.filter { !pinnedGuilds.isPinned($0.guild.id) }.prefix(25))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Venomous Abyss", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated) {
                    showingSettings = true
                }

                Group {
                    if viewModel.standings.isEmpty && viewModel.isLoading {
                        ProgressView("Loading tracker…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.standings.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else if viewModel.standings.isEmpty {
                        List {
                            ContentUnavailableView(
                                "No Standings Yet",
                                systemImage: "list.number",
                                description: Text("Guild standings will appear once the race begins.")
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await viewModel.refresh() }
                    } else {
                        List {
                            if !pinnedStandings.isEmpty {
                                Section {
                                    standingRows(pinnedStandings)
                                } header: {
                                    Text("Pinned")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Section {
                                    standingRows(otherStandings)
                                } header: {
                                    Text("Standings")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            } else {
                                standingRows(otherStandings)
                            }
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

    @ViewBuilder
    private func standingRows(_ standings: [GuildStanding]) -> some View {
        ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
            GuildStandingRow(
                standing: standing,
                totalBosses: viewModel.raid?.encounters.count ?? 8,
                isLast: index == standings.count - 1,
                isPinned: pinnedGuilds.isPinned(standing.guild.id),
                onTogglePin: { pinnedGuilds.toggle(standing.guild.id) }
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }
}

struct GuildStandingRow: View {
    let standing: GuildStanding
    let totalBosses: Int
    let isLast: Bool
    let isPinned: Bool
    let onTogglePin: () -> Void

    /// This row packs rank + name + live status + realm/region + boss progress into one
    /// line — read one Text at a time, VoiceOver users get four-plus disconnected fragments
    /// per guild instead of a sentence. Everything except the pin button (which stays its
    /// own reachable, actionable element) is grouped under this single label instead.
    private var accessibilitySummary: String {
        var parts = ["\(standing.guild.displayName), rank \(standing.rank)"]
        if standing.isLive {
            parts.append("live now")
        }
        parts.append("\(standing.bossesDown) of \(totalBosses) bosses down")
        if let currentBoss = standing.currentBoss {
            if let percent = standing.currentPullPercent, let pulls = standing.currentPullCount {
                parts.append("working on \(currentBoss.name), \(String(format: "%.2f%%", percent)), \(pulls) \(pulls == 1 ? "pull" : "pulls")")
            } else {
                parts.append("working on \(currentBoss.name)")
            }
        }
        parts.append("\(standing.guild.realm.name), \(standing.guild.region.shortName)")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                HStack(spacing: Theme.trackerRowColumnGap) {
                    Text("\(standing.rank)")
                        .font(Theme.rankNumber)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, alignment: .leading)

                    GuildAvatar(guild: standing.guild)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(standing.guild.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if standing.isLive {
                                LiveBadge()
                            }
                        }
                        Text("\(standing.guild.realm.name) · \(standing.guild.region.shortName)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        if let currentBoss = standing.currentBoss {
                            if let percent = standing.currentPullPercent, let pulls = standing.currentPullCount {
                                Text("\(currentBoss.name) — \(String(format: "%.2f%%", percent)) (\(pulls) \(pulls == 1 ? "pull" : "pulls"))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Text("Working on \(currentBoss.name)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(standing.bossesDown)/\(totalBosses) M")
                            .font(Theme.bossProgress)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                        if let killedAt = standing.lastKillAt {
                            TimelineView(.periodic(from: killedAt, by: 1)) { context in
                                Text("For \(RelativeTime.elapsed(since: killedAt, to: context.date))")
                            }
                            .font(Theme.elapsedTimer)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)

                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(isPinned ? Theme.accent : Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPinned ? "Unpin guild" : "Pin guild")
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
    TrackerView()
}

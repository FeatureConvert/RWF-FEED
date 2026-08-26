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
            // ZStack + zero-opacity NavigationLink keeps the row pushing the guild detail
            // screen without List's disclosure chevron changing the row layout; the LIVE
            // badge's own Link sits above it and still wins taps on its own frame.
            ZStack {
                NavigationLink {
                    GuildDetailView(
                        standing: standing,
                        ranking: viewModel.rankingByGuildId[standing.guild.id],
                        encounters: viewModel.raid?.encounters ?? []
                    )
                } label: { EmptyView() }
                .opacity(0)

                GuildStandingRow(
                    standing: standing,
                    totalBosses: viewModel.raid?.encounters.count ?? RaidConstants.bossCount,
                    isLast: index == standings.count - 1,
                    isPinned: pinnedGuilds.isPinned(standing.guild.id),
                    onTogglePin: { pinnedGuilds.toggle(standing.guild.id) }
                )
            }
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

    /// The visible label and its VoiceOver equivalent for `standing.currentPull`, computed once
    /// so the two can't drift out of sync the way two independently-written branches could —
    /// nil when the guild has cleared the raid or raid-rankings has no data for them at all.
    private var currentPullLabel: (visible: String, accessible: String)? {
        guard let currentPull = standing.currentPull else { return nil }
        guard let percent = currentPull.percent, let pulls = currentPull.pullCount else {
            return ("Working on \(currentPull.boss.name)", "working on \(currentPull.boss.name)")
        }
        let percentText = String(format: "%.2f%%", percent)
        return (
            "\(currentPull.boss.name) — \(percentText) remaining (\(pulls.pullsLabel))",
            "working on \(currentPull.boss.name), \(percentText) remaining, \(pulls.pullsLabel)"
        )
    }

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
        if let currentPullLabel {
            parts.append(currentPullLabel.accessible)
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
                            // Purely visual here — kept inside the grouped/ignored HStack below
                            // like every other decorative element in this row. The actual tap
                            // target lives outside that group, next to the pin button, so it
                            // stays independently reachable under VoiceOver (a Link nested
                            // inside an .accessibilityElement(children: .ignore) subtree is
                            // otherwise unreachable — same reasoning as the pin button already
                            // being a sibling of the group, not a child).
                            if standing.isLive {
                                LiveBadge()
                            }
                        }
                        Text("\(standing.guild.realm.name) · \(standing.guild.region.shortName)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        if let currentPullLabel {
                            Text(currentPullLabel.visible)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
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

                if let stream = standing.liveStream, let url = stream.twitchURL {
                    Link(destination: url) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Watch \(standing.guild.displayName)'s live stream")
                }

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

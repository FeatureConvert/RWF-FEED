//
//  BossBreakdownView.swift
//  RWF FEED
//
//  A simple ordered list of bosses: who claimed World First on each, and — for bosses still
//  unclaimed — whichever guild currently has the best (lowest remaining health%) live pull.
//  Pull data comes straight from raider.io's own Desktop App combat-log tracking (see
//  RaidInfo.bossSummaries), so it's real and near real-time, not a proxy. Each row also
//  discloses its top 3 kills (World First plus runners-up) on tap — merged in from the former
//  standalone Kills tab rather than keeping that as a separate screen.
//

import SwiftUI

struct BossBreakdownView: View {
    @StateObject private var viewModel = BossBreakdownViewModel()
    @State private var showingSettings = false
    @State private var showingRecap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bosses collapsed by the user — absent means expanded, so a newly-appearing boss (one
    /// nobody's collapsed yet) always starts expanded rather than needing to be in some
    /// explicit "expanded" set. Matches the former standalone Kills tab's default.
    @State private var collapsedBossIDs: Set<Int> = []
    /// See FeedView's isActive doc comment — ContentView keeps every visited tab mounted, so
    /// polling has to be paused/resumed off this instead of .onDisappear (which never fires).
    var isActive: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Boss List", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated) {
                    showingSettings = true
                }

                if viewModel.isRaceComplete {
                    Button {
                        showingRecap = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            Text("Race Complete — View Final Standings")
                                .font(.rwf(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.rwf(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, Theme.trackerRowHPadding)
                        .padding(.vertical, 12)
                        .background(Theme.cardSurface)
                    }
                    .buttonStyle(.plain)
                }

                Group {
                    if viewModel.summaries.isEmpty && viewModel.isLoading {
                        ProgressView("Loading boss list…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.summaries.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else if viewModel.summaries.isEmpty {
                        List {
                            ContentUnavailableView(
                                "No Bosses Yet",
                                systemImage: "chart.bar",
                                description: Text("The boss list will appear once the raid opens.")
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await viewModel.refresh() }
                    } else {
                        // Plain ScrollView + LazyVStack rather than List — the former standalone
                        // Kills tab used this same structure so each row's chevron/tap gesture
                        // and the kills it discloses are normal SwiftUI views, not fighting
                        // List's UIKit table-cell wrapping (see the Kills tab's original
                        // reasoning, preserved here since that tab's expand/collapse moved in).
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.summaries.enumerated()), id: \.element.id) { index, summary in
                                    let trendKey = summary.bestPull.map { "\($0.guild.id)-\(summary.boss.slug)" }
                                    let kills = viewModel.killsByBossId[summary.boss.id] ?? []
                                    let isExpanded = !collapsedBossIDs.contains(summary.boss.id)
                                    BossSummaryRow(
                                        summary: summary,
                                        trend: trendKey.flatMap { viewModel.pullTrends[$0] },
                                        isLast: index == viewModel.summaries.count - 1,
                                        kills: kills,
                                        isExpanded: isExpanded,
                                        onToggle: kills.isEmpty ? nil : {
                                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                                if isExpanded {
                                                    collapsedBossIDs.insert(summary.boss.id)
                                                } else {
                                                    collapsedBossIDs.remove(summary.boss.id)
                                                }
                                            }
                                        }
                                    )
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
        .sheet(isPresented: $showingRecap) {
            RaceCompleteRecapView(standings: viewModel.finalStandings, summaries: viewModel.summaries)
        }
    }
}

struct BossSummaryRow: View {
    let summary: BossSummary
    let trend: PullTrend?
    let isLast: Bool
    /// Up to the top 3 kills on this boss (World First plus runners-up) — empty until anyone's
    /// downed it, which is when this row becomes expandable at all.
    var kills: [KillFeedEvent] = []
    var isExpanded: Bool = false
    /// Nil when there's nothing to disclose (`kills.isEmpty`) — the row skips the chevron and
    /// tap gesture entirely rather than expanding to nothing.
    var onToggle: (() -> Void)? = nil

    /// Combines the ordinal, boss name, and current status (World First / best pull / not
    /// reached) into one sentence — rank number and the trailing timestamp are folded in
    /// here too (and hidden individually below) so the whole row reads as one coherent stop
    /// instead of four-plus disconnected Text fragments. The "Watch the Kill" link is
    /// deliberately left out of this group (and out of scope entirely) so it stays its own
    /// independently-reachable, actionable VoiceOver element.
    private var accessibilitySummary: String {
        var parts = ["Boss \(summary.boss.ordinal + 1), \(summary.boss.name)"]
        if let worldFirst = summary.worldFirst {
            parts.append("World First by \(worldFirst.guild.displayName)")
            parts.append(RelativeTime.short(from: worldFirst.at))
        } else if let bestPull = summary.bestPull {
            parts.append("Best pull \(String(format: "%.2f%%", bestPull.percent)) remaining by \(bestPull.guild.displayName), \(bestPull.pullCount.pullsLabel)")
            if let trend {
                parts.append(trend.isStalled ? "holding steady" : String(format: "%+.1f%% in the last hour", trend.percentChange))
            }
        } else {
            parts.append("Not yet reached")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if isExpanded {
                ForEach(Array(kills.enumerated()), id: \.element.id) { index, event in
                    KillFeedRow(event: event, isLast: index == kills.count - 1)
                        .padding(.leading, Theme.trackerRowHPadding + 22 + Theme.trackerRowColumnGap)
                }
            }

            if !isLast {
                FadingDivider()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: Theme.trackerRowColumnGap) {
            Text("\(summary.boss.ordinal + 1)")
                .font(Theme.rankNumber)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, alignment: .leading)
                // Folded into accessibilitySummary above.
                .accessibilityHidden(true)

            AsyncImage(url: summary.boss.fullIconURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.clear
                }
            }
            .frame(width: Theme.guildLogoDiameter, height: Theme.guildLogoDiameter)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Group {
                    Text(summary.boss.name)
                        .font(.rwf(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if let worldFirst = summary.worldFirst {
                        HStack(spacing: 4) {
                            WorldFirstBadge()
                            Text(worldFirst.guild.displayName)
                                .font(.rwf(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if let bestPull = summary.bestPull {
                        Text("Best pull \(String(format: "%.2f%%", bestPull.percent)) remaining — \(bestPull.guild.displayName) (\(bestPull.pullCount.pullsLabel))")
                            .font(.rwf(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        if let trend {
                            PullTrendLabel(trend: trend)
                        }
                    } else {
                        Text("Not yet reached")
                            .font(.rwf(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                // The chevron itself is decorative (accessibilityHidden below) — its
                // expanded/collapsed state and toggle action live here instead, on the row's
                // one coherent VoiceOver stop, rather than needing its own reachable element.
                .modifier(ExpandableRowAccessibility(onToggle: onToggle, isExpanded: isExpanded))

                if let worldFirst = summary.worldFirst, let vodURL = worldFirst.vodURL {
                    Link(destination: vodURL) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                            Text("Watch the Kill")
                        }
                        .font(.rwf(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                    }
                    .accessibilityLabel("Watch the kill VOD")
                }
            }

            Spacer()

            if let worldFirst = summary.worldFirst {
                Text(RelativeTime.short(from: worldFirst.at))
                    .font(.rwf(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    // Folded into accessibilitySummary above.
                    .accessibilityHidden(true)
            }

            if onToggle != nil {
                Image(systemName: "chevron.down")
                    .font(.rwf(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    // Folded into accessibilityValue above.
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Theme.trackerRowVPadding)
        .padding(.horizontal, Theme.trackerRowHPadding)
        .contentShape(Rectangle())
        .onTapGesture { onToggle?() }
    }
}

/// Only wires up expand/collapse semantics when there's something to toggle (`onToggle` is nil
/// for bosses nobody's killed yet) — the row skips the trait/value/action entirely rather than
/// exposing a control that expands to an empty kill list.
private struct ExpandableRowAccessibility: ViewModifier {
    let onToggle: (() -> Void)?
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if let onToggle {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityAction {
                    onToggle()
                }
        } else {
            content
        }
    }
}

/// One kill row nested under a boss's disclosed top-3 list — moved in from the former
/// standalone Kills tab.
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
                    .font(.rwf(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if event.rank == 1 {
                        WorldFirstBadge()
                    } else {
                        Text(event.rankLabel)
                            .font(.rwf(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(RelativeTime.short(from: event.defeatedAt))
                        .font(.rwf(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, Theme.trackerRowHPadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            if !isLast {
                FadingDivider()
            }
        }
    }
}

#Preview {
    BossBreakdownView()
}

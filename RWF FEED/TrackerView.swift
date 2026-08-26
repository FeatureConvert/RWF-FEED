//
//  TrackerView.swift
//  RWF FEED
//

import SwiftUI

struct TrackerView: View {
    @StateObject private var viewModel = TrackerViewModel()
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
                        List(Array(viewModel.standings.enumerated()), id: \.element.id) { index, standing in
                            // ZStack + zero-opacity NavigationLink keeps the row pushing the
                            // guild detail screen without List's disclosure chevron changing
                            // the row layout; the LIVE badge's own Link sits above it and
                            // still wins taps on its own frame.
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
                                    totalBosses: viewModel.raid?.encounters.count ?? 8,
                                    isLast: index == viewModel.standings.count - 1
                                )
                            }
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

struct GuildStandingRow: View {
    let standing: GuildStanding
    let totalBosses: Int
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
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
                        if let stream = standing.liveStream, let url = stream.twitchURL {
                            Link(destination: url) {
                                LiveBadge()
                            }
                            .buttonStyle(.plain)
                        } else if standing.isLive {
                            LiveBadge()
                        }
                    }
                    Text("\(standing.guild.realm.name) · \(standing.guild.region.shortName)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
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
            .padding(.horizontal, Theme.trackerRowHPadding)
            .padding(.top, Theme.trackerRowVPadding)
            .padding(.bottom, standing.rank <= 5 && standing.currentPull != nil ? 0 : Theme.trackerRowVPadding)

            if standing.rank <= 5, let pull = standing.currentPull {
                CurrentPullRow(pull: pull)
                    .padding(.leading, Theme.trackerRowHPadding + Theme.guildLogoDiameter + Theme.trackerRowColumnGap)
                    .padding(.trailing, Theme.trackerRowHPadding)
                    .padding(.top, 4)
                    .padding(.bottom, Theme.trackerRowVPadding)
            }

            if !isLast {
                FadingDivider()
            }
        }
    }
}

/// Shown only on the top 5 guilds' rows — the boss they're currently pulling and their best
/// live progress on it, from raid-rankings. Absent (row omits this entirely) once a guild's
/// killed every boss, or before raid-rankings has recorded a pull on their next one yet.
private struct CurrentPullRow: View {
    let pull: GuildStanding.CurrentPull

    var body: some View {
        HStack(spacing: 6) {
            AsyncImage(url: pull.boss.fullIconURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            Text("On \(pull.boss.name)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(String(format: "%.2f%%", pull.percent))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .monospacedDigit()

            Text("· \(pull.pullCount) pulls")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    TrackerView()
}

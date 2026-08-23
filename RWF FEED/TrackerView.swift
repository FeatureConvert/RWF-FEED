//
//  TrackerView.swift
//  RWF FEED
//

import SwiftUI

struct TrackerView: View {
    @StateObject private var viewModel = TrackerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Venomous Abyss", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated)

                Group {
                    if viewModel.standings.isEmpty && viewModel.isLoading {
                        ProgressView("Loading tracker…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.standings.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else {
                        List(Array(viewModel.standings.enumerated()), id: \.element.id) { index, standing in
                            GuildStandingRow(
                                rank: index + 1,
                                standing: standing,
                                totalBosses: viewModel.raid?.encounters.count ?? 8,
                                isLast: index == viewModel.standings.count - 1
                            )
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
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

struct GuildStandingRow: View {
    let rank: Int
    let standing: GuildStanding
    let totalBosses: Int
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                Text("\(rank)")
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

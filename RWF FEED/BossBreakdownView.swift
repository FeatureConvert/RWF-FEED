//
//  BossBreakdownView.swift
//  RWF FEED
//
//  A simple ordered list of bosses: who claimed World First on each, and — for bosses still
//  unclaimed — whichever guild currently has the best (lowest remaining health%) live pull.
//  Pull data comes straight from raider.io's own Desktop App combat-log tracking (see
//  RaidInfo.bossSummaries), so it's real and near real-time, not a proxy.
//

import SwiftUI

struct BossBreakdownView: View {
    @StateObject private var viewModel = BossBreakdownViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Boss List", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated)

                Group {
                    if viewModel.summaries.isEmpty && viewModel.isLoading {
                        ProgressView("Loading boss list…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.summaries.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else {
                        List(Array(viewModel.summaries.enumerated()), id: \.element.id) { index, summary in
                            BossSummaryRow(summary: summary, isLast: index == viewModel.summaries.count - 1)
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

struct BossSummaryRow: View {
    let summary: BossSummary
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                Text("\(summary.boss.ordinal + 1)")
                    .font(Theme.rankNumber)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, alignment: .leading)

                AsyncImage(url: summary.boss.fullIconURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Theme.guildLogoDiameter, height: Theme.guildLogoDiameter)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.boss.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if let worldFirst = summary.worldFirst {
                        HStack(spacing: 4) {
                            Text("WORLD FIRST")
                                .font(Theme.liveBadgeLabel)
                                .tracking(Theme.liveBadgeTracking)
                                .foregroundStyle(Color(hex: "#292B31"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "#D2CEFD"), in: Capsule())
                            Text(worldFirst.guild.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if let bestPull = summary.bestPull {
                        Text("Best pull \(String(format: "%.2f%%", bestPull.percent)) — \(bestPull.guild.displayName) (\(bestPull.pullCount) pulls)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Not yet reached")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                if let worldFirst = summary.worldFirst {
                    Text(RelativeTime.short(from: worldFirst.at))
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
    BossBreakdownView()
}

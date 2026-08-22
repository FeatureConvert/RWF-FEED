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
                ScreenHeader(title: "Venomous Abyss", isLoading: viewModel.isLoading)

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

                GuildAvatar(standing: standing)

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

private struct GuildAvatar: View {
    let standing: GuildStanding

    private static let palette: [(background: Color, foreground: Color)] = [
        (Color(hex: "#5D5294"), .white),
        (Color(hex: "#796CBF"), .white),
        (Color.adaptive(darkHex: "#75798C", lightHex: "#9397AB"), .white),
        (Color(hex: "#B5ABFC"), Color(hex: "#292B31")),
    ]

    private var initials: String {
        let words = standing.guild.displayName.split(separator: " ")
        if words.count >= 2 {
            return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(standing.guild.displayName.prefix(2)).uppercased()
    }

    private var colors: (background: Color, foreground: Color) {
        Self.palette[abs(standing.guild.id) % Self.palette.count]
    }

    var body: some View {
        AsyncImage(url: URL(string: standing.guild.logo)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Circle().fill(colors.background)
                    Text(initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.foreground)
                }
            }
        }
        .frame(width: Theme.guildLogoDiameter, height: Theme.guildLogoDiameter)
        .clipShape(Circle())
    }
}

private struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(Theme.liveBadgeLabel)
            .tracking(Theme.liveBadgeTracking)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.live, in: Capsule())
    }
}

/// A hairline rule that fades to transparent 24pt from each edge, matching the spec's
/// "Tracker row divider" note.
private struct FadingDivider: View {
    var body: some View {
        GeometryReader { geo in
            let fade = min(24, geo.size.width / 4)
            let start = fade / geo.size.width
            let end = 1 - start
            LinearGradient(
                stops: [
                    .init(color: Theme.divider.opacity(0), location: 0),
                    .init(color: Theme.divider, location: start),
                    .init(color: Theme.divider, location: end),
                    .init(color: Theme.divider.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
        .frame(height: 1)
    }
}

#Preview {
    TrackerView()
}

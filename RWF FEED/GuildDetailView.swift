//
//  GuildDetailView.swift
//  RWF FEED
//
//  Pushed from a Tracker row: one guild's full race progression, boss by boss — kill times
//  and pull counts for downed bosses, live best-pull progress on the one they're working on.
//  Everything renders from data the Tracker already fetched (raid-rankings entry + raid
//  encounter metadata); this screen adds no network calls of its own beyond boss icons.
//

import SwiftUI

struct GuildDetailView: View {
    let standing: GuildStanding
    /// The guild's full raid-rankings entry. Practically always present (standings are built
    /// from these same entries); nil only if a refresh replaced the rankings between the tap
    /// and the push, in which case bosses show as "Not yet reached" until the next poll.
    let ranking: RaidRankingEntry?
    let encounters: [Encounter]

    private enum BossStatus {
        case killed(at: Date, pullCount: Int?)
        case inProgress(bestPercent: Double, pullCount: Int?)
        case notReached
    }

    private var bossRows: [(boss: Encounter, status: BossStatus)] {
        let defeatBySlug = Dictionary(
            (ranking?.encountersDefeated ?? []).map { ($0.slug, $0.firstDefeated) },
            uniquingKeysWith: { first, _ in first }
        )
        let pullBySlug = Dictionary(
            (ranking?.encountersPulled ?? []).map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return encounters
            .sorted { $0.ordinal < $1.ordinal }
            .map { boss in
                if let killedAt = defeatBySlug[boss.slug] {
                    return (boss, .killed(at: killedAt, pullCount: pullBySlug[boss.slug]?.numPulls))
                }
                if let pull = pullBySlug[boss.slug], !pull.isDefeated, let percent = pull.bestPercent {
                    return (boss, .inProgress(bestPercent: percent, pullCount: pull.numPulls))
                }
                return (boss, .notReached)
            }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: 4, leading: Theme.trackerRowHPadding,
                        bottom: 10, trailing: Theme.trackerRowHPadding
                    ))
            }

            Section {
                let rows = bossRows
                ForEach(Array(rows.enumerated()), id: \.element.boss.id) { index, row in
                    BossStatusRow(boss: row.boss, status: row.status, isLast: index == rows.count - 1)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(standing.guild.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                GuildAvatar(guild: standing.guild)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(standing.guild.displayName)
                        .font(.rwf(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(standing.guild.realm.name) · \(standing.guild.region.shortName)")
                        .font(.rwf(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("#\(standing.rank) World")
                        .font(Theme.bossProgress)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(standing.bossesDown)/\(encounters.count) M")
                        .font(.rwf(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(standing.guild.displayName), \(standing.guild.realm.name), \(standing.guild.region.shortName), "
                + "rank \(standing.rank) world, \(standing.bossesDown) of \(encounters.count) bosses down"
            )

            if let stream = standing.liveStream, let url = stream.twitchURL {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        LiveBadge()
                            .accessibilityHidden(true)
                        Text(streamLabel(stream))
                            .font(.rwf(size: 12))
                            .foregroundStyle(Theme.accentText)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch live: \(streamLabel(stream))")
            }
        }
    }

    private func streamLabel(_ stream: LiveStream) -> String {
        var label = stream.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty { label = stream.channelName }
        if let viewers = stream.viewerCount {
            label += " · \(viewers) watching"
        }
        return label
    }

    private struct BossStatusRow: View {
        let boss: Encounter
        let status: BossStatus
        let isLast: Bool

        private var accessibilitySummary: String {
            var parts = ["Boss \(boss.ordinal + 1), \(boss.name)"]
            switch status {
            case .killed(let at, let pullCount):
                parts.append("killed \(RelativeTime.short(from: at))")
                if let pullCount { parts.append(pullCount.pullsLabel) }
            case .inProgress(let bestPercent, let pullCount):
                parts.append("in progress, \(String(format: "%.2f%%", bestPercent)) remaining")
                if let pullCount { parts.append(pullCount.pullsLabel) }
            case .notReached:
                parts.append("not yet reached")
            }
            return parts.joined(separator: ", ")
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: Theme.trackerRowColumnGap) {
                    Text("\(boss.ordinal + 1)")
                        .font(Theme.rankNumber)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, alignment: .leading)
                        .accessibilityHidden(true)

                    AsyncImage(url: boss.fullIconURL) { phase in
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
                        Text(boss.name)
                            .font(.rwf(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .font(.rwf(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    trailing
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                .padding(.vertical, Theme.trackerRowVPadding)
                .padding(.horizontal, Theme.trackerRowHPadding)

                if !isLast {
                    FadingDivider()
                }
            }
        }

        private var subtitle: String {
            switch status {
            case .killed(let at, let pullCount):
                let relative = RelativeTime.short(from: at)
                // RelativeTime.short's under-a-minute case is the phrase "just now", which
                // doesn't compose with the "ago" suffix the m/h/d forms need.
                let when = relative == "just now" ? "Killed just now" : "Killed \(relative) ago"
                // numPulls is genuinely absent (not zero) for some already-defeated
                // encounters — see EncounterPullEntry — so only mention pulls when known.
                if let pullCount {
                    return "\(when) · \(pullCount.pullsLabel)"
                }
                return when
            case .inProgress(let bestPercent, let pullCount):
                if let pullCount {
                    return "\(String(format: "%.2f%%", bestPercent)) remaining · \(pullCount.pullsLabel)"
                }
                return "\(String(format: "%.2f%%", bestPercent)) remaining"
            case .notReached:
                return "Not yet reached"
            }
        }

        @ViewBuilder
        private var trailing: some View {
            switch status {
            case .killed:
                Image(systemName: "checkmark.seal.fill")
                    .font(.rwf(size: 18))
                    .foregroundStyle(Theme.accent)
            case .inProgress(let bestPercent, _):
                Text(String(format: "%.2f%%", bestPercent))
                    .font(.rwf(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accentText)
                    .monospacedDigit()
            case .notReached:
                EmptyView()
            }
        }
    }
}

#Preview {
    NavigationStack {
        GuildDetailView(
            standing: GuildStanding(
                guild: RaceGuild(
                    id: 1, name: "liquid", displayName: "Liquid", faction: "alliance",
                    realm: RealmRef(name: "Illidan"), region: RegionRef(name: "United States", slug: "us", shortName: "US"),
                    path: "/guilds/us/illidan/liquid", logo: "", color: nil
                ),
                rank: 1, bossesDown: 5, lastKillAt: Date(), liveStream: nil, currentPull: nil
            ),
            ranking: nil,
            encounters: []
        )
    }
}

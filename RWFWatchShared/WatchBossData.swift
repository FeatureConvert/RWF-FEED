//
//  WatchBossData.swift
//  Shared between the RWFFeedWatch app and RWFFeedWatchWidget complication targets.
//
//  A small, self-contained copy of just the raider.io fetching/decoding the watch side needs
//  — mirrors RWFFeedWidget/WidgetData.swift (the iOS widget's copy) rather than sharing code
//  across all three extensions, to keep each target's build graph simple.
//

import Foundation

private struct RaidRaceResponse: Decodable {
    let worldFirstTracker: WorldFirstTracker
}

private struct WorldFirstTracker: Decodable {
    let raid: RaidInfo
}

private struct RaidInfo: Decodable {
    let encounters: [EncounterRef]
}

private struct EncounterRef: Decodable {
    let name: String
    let slug: String
    let ordinal: Int
    let iconUrl: String
}

private struct RaidRankingsResponse: Decodable {
    let raidRankings: [RaidRankingEntry]
}

private struct RaidRankingEntry: Decodable {
    let guild: GuildRef
    let encountersDefeated: [EncounterDefeatEntry]
    let encountersPulled: [EncounterPullEntry]
}

private struct EncounterDefeatEntry: Decodable {
    let slug: String
}

private struct GuildRef: Decodable {
    let displayName: String
}

private struct EncounterPullEntry: Decodable {
    let slug: String
    let numPulls: Int?
    let bestPercent: Double?
    let isDefeated: Bool
}

struct WatchGuildStanding: Codable {
    let guildName: String
    let bossesDown: Int
}

struct WatchBossState: Codable {
    let bossName: String
    let bossOrdinal: Int
    let totalBosses: Int
    let iconUrl: String
    let bestGuildName: String?
    let bestPercent: Double?
    let pullCount: Int?
    let top3: [WatchGuildStanding]

    var fullIconURL: URL? { URL(string: "https://cdn.raiderio.net\(iconUrl)") }

    static let placeholder = WatchBossState(
        bossName: "Entombed Sentinels", bossOrdinal: 1, totalBosses: 8, iconUrl: "",
        bestGuildName: "xD", bestPercent: 63.01, pullCount: 6,
        top3: [
            WatchGuildStanding(guildName: "xD", bossesDown: 6),
            WatchGuildStanding(guildName: "Liquid", bossesDown: 5),
            WatchGuildStanding(guildName: "Echo", bossesDown: 5),
        ]
    )
}

enum RWFWatchData {
    private static let raidSlug = "the-venomous-abyss"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoderInner in
            let container = try decoderInner.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }()

    private static let cacheKey = "RWFWatchData.lastKnownBossState"

    /// The leading guild's (by confirmed kills) own next boss, plus whichever guild has the
    /// best (lowest remaining health%) live pull on it. Deliberately anchored on the actual
    /// leader's frontier rather than "whichever boss anyone has the highest-ordinal active pull
    /// on" (the previous approach) — a guild merely scouting/wiping on a later boss without
    /// having cleared the ones before it isn't actually ahead, and showing them as the headline
    /// guild was misleading. Falls back to the last successfully-fetched state (persisted in
    /// UserDefaults) on any network/decode failure, so a transient blip doesn't blank the watch
    /// app/complications until the next budgeted refresh.
    static func fetchCurrentBoss() async -> WatchBossState? {
        if let fresh = await fetchFreshBoss() {
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            return fresh
        }
        guard let cached = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WatchBossState.self, from: cached)
    }

    private static func fetchFreshBoss() async -> WatchBossState? {
        do {
            async let encountersTask = fetchEncounters()
            async let rankingsTask = fetchRankings()
            let (encounters, rankings) = try await (encountersTask, rankingsTask)

            var bestPullBySlug: [String: (guild: String, percent: Double, pullCount: Int)] = [:]
            for entry in rankings {
                for pull in entry.encountersPulled where !pull.isDefeated {
                    guard let percent = pull.bestPercent, let pullCount = pull.numPulls else { continue }
                    let current = bestPullBySlug[pull.slug]
                    if current == nil || percent < current!.percent {
                        bestPullBySlug[pull.slug] = (entry.guild.displayName, percent, pullCount)
                    }
                }
            }

            // The leader is whoever's confirmed at least as many kills as anyone else — not
            // whoever has the highest-ordinal boss with an active pull recorded against it.
            guard let leader = rankings.max(by: { $0.encountersDefeated.count < $1.encountersDefeated.count }) else {
                return nil
            }
            let defeatedByLeader = Set(leader.encountersDefeated.map(\.slug))
            guard let boss = encounters.sorted(by: { $0.ordinal < $1.ordinal }).first(where: { !defeatedByLeader.contains($0.slug) }) else {
                return nil // leader has cleared every boss in the raid
            }
            let best = bestPullBySlug[boss.slug]

            // Same confirmed-kill-count ranking as the leader above, just keeping the top 3
            // instead of only the winner.
            let top3 = rankings
                .sorted(by: { $0.encountersDefeated.count > $1.encountersDefeated.count })
                .prefix(3)
                .map { WatchGuildStanding(guildName: $0.guild.displayName, bossesDown: $0.encountersDefeated.count) }

            return WatchBossState(
                bossName: boss.name, bossOrdinal: boss.ordinal + 1, totalBosses: encounters.count, iconUrl: boss.iconUrl,
                bestGuildName: best?.guild, bestPercent: best?.percent, pullCount: best?.pullCount,
                top3: Array(top3)
            )
        } catch {
            return nil
        }
    }

    private static func fetchEncounters() async throws -> [EncounterRef] {
        var components = URLComponents(string: "https://raider.io/api/raids/raid-race")!
        components.queryItems = [
            URLQueryItem(name: "raid", value: raidSlug),
            URLQueryItem(name: "region", value: "world"),
            URLQueryItem(name: "difficulty", value: "mythic"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(RaidRaceResponse.self, from: data).worldFirstTracker.raid.encounters
    }

    private static func fetchRankings() async throws -> [RaidRankingEntry] {
        var components = URLComponents(string: "https://raider.io/api/v1/raiding/raid-rankings")!
        components.queryItems = [
            URLQueryItem(name: "raid", value: raidSlug),
            URLQueryItem(name: "difficulty", value: "mythic"),
            URLQueryItem(name: "region", value: "world"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(RaidRankingsResponse.self, from: data).raidRankings
    }
}

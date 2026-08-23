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
    let encountersPulled: [EncounterPullEntry]
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

struct WatchBossState: Codable {
    let bossName: String
    let bossOrdinal: Int
    let totalBosses: Int
    let iconUrl: String
    let bestGuildName: String?
    let bestPercent: Double?
    let pullCount: Int?

    var fullIconURL: URL? { URL(string: "https://cdn.raiderio.net\(iconUrl)") }

    static let placeholder = WatchBossState(
        bossName: "Entombed Sentinels", bossOrdinal: 1, totalBosses: 8, iconUrl: "",
        bestGuildName: "xD", bestPercent: 63.01, pullCount: 6
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

    /// The furthest-progressed boss anyone is currently pulling, plus whichever guild has the
    /// best (lowest remaining health%) live pull on it. Falls back to the last successfully-
    /// fetched state (persisted in UserDefaults) on any network/decode failure, so a transient
    /// blip doesn't blank the watch app/complications until the next budgeted refresh.
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

            let encounterBySlug = Dictionary(uniqueKeysWithValues: encounters.map { ($0.slug, $0) })

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

            guard let frontierSlug = bestPullBySlug.keys.max(by: { (encounterBySlug[$0]?.ordinal ?? -1) < (encounterBySlug[$1]?.ordinal ?? -1) }),
                  let boss = encounterBySlug[frontierSlug] else {
                return nil
            }
            let best = bestPullBySlug[frontierSlug]

            return WatchBossState(
                bossName: boss.name, bossOrdinal: boss.ordinal + 1, totalBosses: encounters.count, iconUrl: boss.iconUrl,
                bestGuildName: best?.guild, bestPercent: best?.percent, pullCount: best?.pullCount
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
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try decoder.decode(RaidRaceResponse.self, from: data).worldFirstTracker.raid.encounters
    }

    private static func fetchRankings() async throws -> [RaidRankingEntry] {
        var components = URLComponents(string: "https://raider.io/api/v1/raiding/raid-rankings")!
        components.queryItems = [
            URLQueryItem(name: "raid", value: raidSlug),
            URLQueryItem(name: "difficulty", value: "mythic"),
            URLQueryItem(name: "region", value: "world"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try decoder.decode(RaidRankingsResponse.self, from: data).raidRankings
    }
}

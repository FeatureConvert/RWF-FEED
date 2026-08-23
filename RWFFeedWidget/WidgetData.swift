//
//  WidgetData.swift
//  RWFFeedWidget
//
//  A small, self-contained copy of just the raider.io fetching/decoding this widget needs.
//  Kept independent from the main app target's RaiderIOService/Models so this extension has
//  no cross-target source dependency to wire up — see the main target's RaiderIOService.swift
//  for the fuller version of the same API shapes, with more detailed commentary.
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

struct WidgetBossState: Codable {
    let bossName: String
    let bossOrdinal: Int
    let totalBosses: Int
    /// Pre-fetched during the timeline provider phase — AsyncImage inside the widget view
    /// itself is unreliable since the extension process is often suspended right after
    /// rendering, before a network image load can complete.
    let iconData: Data?
    let bestGuildName: String?
    let bestPercent: Double?
    let pullCount: Int?

    static let placeholder = WidgetBossState(
        bossName: "Entombed Sentinels", bossOrdinal: 1, totalBosses: 8, iconData: nil,
        bestGuildName: "xD", bestPercent: 63.01, pullCount: 6
    )
}

enum RWFWidgetData {
    private static let raidSlug = "the-venomous-abyss"
    /// Scoped to this extension's own sandboxed UserDefaults — no App Group needed, since
    /// this only needs to survive across this widget's own process invocations, not be
    /// shared with the main app.
    private static let cacheKey = "RWFWidgetData.lastKnownBossState"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // raid-race's dates come back with fractional seconds; raid-rankings' don't — accept
        // both rather than only the format whichever field happened to be tested against.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoderInner in
            let container = try decoderInner.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso.date(from: string) { return date }
            if let date = isoNoFraction.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }()

    /// The furthest-progressed boss anyone is currently pulling (max ordinal among every
    /// guild's live, not-yet-defeated pull), plus whichever guild has the best (lowest
    /// remaining health%) live pull on it. Falls back to the last successfully-fetched state
    /// (cached in this extension's own UserDefaults) on any network/decode failure, or when
    /// nobody currently has a live pull — nil only if we've never successfully fetched at all.
    static func fetchCurrentBoss() async -> WidgetBossState? {
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
                return loadCachedState()
            }
            let best = bestPullBySlug[frontierSlug]
            let iconData = try? await fetchIconData(path: boss.iconUrl)

            let state = WidgetBossState(
                bossName: boss.name, bossOrdinal: boss.ordinal + 1, totalBosses: encounters.count, iconData: iconData,
                bestGuildName: best?.guild, bestPercent: best?.percent, pullCount: best?.pullCount
            )
            cache(state)
            return state
        } catch {
            return loadCachedState()
        }
    }

    private static func cache(_ state: WidgetBossState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private static func loadCachedState() -> WidgetBossState? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetBossState.self, from: data)
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

    private static func fetchIconData(path: String) async throws -> Data {
        guard let url = URL(string: "https://cdn.raiderio.net\(path)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
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

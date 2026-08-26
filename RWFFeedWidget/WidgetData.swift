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

struct WidgetGuildStanding: Codable, Identifiable {
    let guildName: String
    let bossesDown: Int

    var id: String { guildName }
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
    /// Top 5 guilds by confirmed kills — only rendered by the large/extra-large families, which
    /// otherwise have far more space than the frontier-boss summary alone fills. Computed from
    /// the same raid-rankings fetch the frontier-boss logic already needs, no extra request.
    let topGuilds: [WidgetGuildStanding]

    static let placeholder = WidgetBossState(
        bossName: "Entombed Sentinels", bossOrdinal: 1, totalBosses: 8, iconData: nil,
        bestGuildName: "xD", bestPercent: 63.01, pullCount: 6,
        topGuilds: [
            WidgetGuildStanding(guildName: "xD", bossesDown: 4),
            WidgetGuildStanding(guildName: "Unluck", bossesDown: 4),
            WidgetGuildStanding(guildName: "Sabotage", bossesDown: 3),
            WidgetGuildStanding(guildName: "Liquid", bossesDown: 3),
            WidgetGuildStanding(guildName: "Humble", bossesDown: 3),
        ]
    )
}

enum RWFWidgetData {
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

    private static let cacheKey = "RWFWidgetData.lastKnownBossState"

    /// The leading guild's (by confirmed kills) own next boss, plus whichever guild has the
    /// best (lowest remaining health%) live pull on it. Deliberately anchored on the actual
    /// leader's frontier rather than "whichever boss anyone has the highest-ordinal active pull
    /// on" (the previous approach) — a guild merely scouting/wiping on a later boss without
    /// having cleared the ones before it isn't actually ahead, and showing them as the headline
    /// guild was misleading. Falls back to the last successfully-fetched state (persisted in
    /// UserDefaults — no App Group needed, this extension only ever needs its own last value)
    /// on any network/decode failure, so a transient blip blanks the widget for one WidgetKit
    /// refresh cycle rather than until the next one succeeds, which can be 15+ minutes away
    /// under system budgeting.
    static func fetchCurrentBoss() async -> WidgetBossState? {
        if let fresh = await fetchFreshBoss() {
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            return fresh
        }
        guard let cached = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetBossState.self, from: cached)
    }

    private static func fetchFreshBoss() async -> WidgetBossState? {
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
            let iconData = try? await fetchIconData(path: boss.iconUrl)

            let topGuilds = rankings
                .map { WidgetGuildStanding(guildName: $0.guild.displayName, bossesDown: $0.encountersDefeated.count) }
                .filter { $0.bossesDown > 0 }
                .sorted { $0.bossesDown > $1.bossesDown }
                .prefix(5)

            return WidgetBossState(
                bossName: boss.name, bossOrdinal: boss.ordinal + 1, totalBosses: encounters.count, iconData: iconData,
                bestGuildName: best?.guild, bestPercent: best?.percent, pullCount: best?.pullCount,
                topGuilds: Array(topGuilds)
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
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
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
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return try decoder.decode(RaidRankingsResponse.self, from: data).raidRankings
    }

    /// Mirrors RaiderIOService's own `validate(_:)` — without this, a non-2xx response (e.g. a
    /// maintenance page or rate-limit response with an HTML/error body) relied entirely on JSON
    /// decode failure to be caught, which happens to work today but isn't guaranteed for every
    /// possible error body shape.
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}

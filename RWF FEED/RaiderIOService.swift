//
//  RaiderIOService.swift
//  RWF FEED
//
//  Talks to the public raider.io JSON endpoints that back the
//  Global Coverage page for a Race to World First raid.
//

import Foundation

enum RaiderIOError: Error {
    case badResponse
}

final class RaiderIOService {
    static let shared = RaiderIOService()

    /// Slug for the raid whose global coverage feed / tracker we show.
    let raidSlug = "the-venomous-abyss"
    let feedSlug = "the-venomous-abyss-global-coverage"

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoderInner in
            let container = try decoderInner.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso.date(from: string) { return date }
            if let date = isoNoFraction.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date format: \(string)")
        }
        return decoder
    }()

    private let session = URLSession(configuration: .default)

    func fetchFeed() async throws -> [FeedPost] {
        var components = URLComponents(string: "https://raider.io/api/threads/list")!
        components.queryItems = [URLQueryItem(name: "slug", value: feedSlug)]
        let (data, response) = try await session.data(from: components.url!)
        try Self.validate(response)
        let decoded = try decoder.decode(ThreadListResponse.self, from: data)
        return decoded.posts
            .filter { !$0.isDeleted }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func fetchTracker(region: String = "world", difficulty: String = "mythic") async throws -> WorldFirstTracker {
        var components = URLComponents(string: "https://raider.io/api/raids/raid-race")!
        components.queryItems = [
            URLQueryItem(name: "raid", value: raidSlug),
            URLQueryItem(name: "region", value: region),
            URLQueryItem(name: "difficulty", value: difficulty),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try Self.validate(response)
        let decoded = try decoder.decode(RaidRaceResponse.self, from: data)
        return decoded.worldFirstTracker
    }

    /// The documented `/raiding/raid-rankings` endpoint (see raider.io/api) — unlike
    /// fetchTracker's boss-count timeline, this carries each guild's live pull data (best %,
    /// pull count) sourced from raider.io's own Desktop App combat-log tracking.
    func fetchRaidRankings(region: String = "world", difficulty: String = "mythic") async throws -> [RaidRankingEntry] {
        var components = URLComponents(string: "https://raider.io/api/v1/raiding/raid-rankings")!
        components.queryItems = [
            URLQueryItem(name: "raid", value: raidSlug),
            URLQueryItem(name: "difficulty", value: difficulty),
            URLQueryItem(name: "region", value: region),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try Self.validate(response)
        let decoded = try decoder.decode(RaidRankingsResponse.self, from: data)
        return decoded.raidRankings
    }

    /// The documented `/raiding/hall-of-fame` endpoint — one entry per boss (in raid order,
    /// including bosses nobody's killed yet, which come back with a nil `bossKillVideo`),
    /// carrying Twitch VOD references for the moment of the world-first kill when one was
    /// captured.
    func fetchHallOfFame(region: String = "world", difficulty: String = "mythic") async throws -> [HallOfFameBossKill] {
        var components = URLComponents(string: "https://raider.io/api/v1/raiding/hall-of-fame")!
        components.queryItems = [
            URLQueryItem(name: "raid", value: raidSlug),
            URLQueryItem(name: "difficulty", value: difficulty),
            URLQueryItem(name: "region", value: region),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try Self.validate(response)
        let decoded = try decoder.decode(HallOfFameResponse.self, from: data)
        return decoded.hallOfFame.bossKills
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RaiderIOError.badResponse
        }
    }
}

// MARK: - Deriving per-guild standings from the timeline buckets

extension WorldFirstTracker {
    private struct BestProgress {
        let guild: RaceGuild
        let progress: Int
        let killedAt: Date?
        let isLive: Bool
    }

    private func timeline(regionSlug: String) -> [ProgressStep] {
        timelines.first(where: { $0.region.slug == regionSlug })?.timeline
            ?? timelines.first?.timeline
            ?? []
    }

    /// One entry per guild: the highest progress they've reached, when they got there, and
    /// whether they're currently streaming — shared by every view below that ranks guilds.
    private func bestProgressPerGuild(_ timeline: [ProgressStep]) -> [Int: BestProgress] {
        var best: [Int: BestProgress] = [:]
        for step in timeline {
            for kill in step.guilds {
                let current = best[kill.guild.id]
                if current == nil || step.progress > current!.progress {
                    best[kill.guild.id] = BestProgress(
                        guild: kill.guild, progress: step.progress, killedAt: kill.defeatedAt,
                        isLive: kill.streamers.count > 0
                    )
                }
            }
        }
        return best
    }

    /// Flattens the per-boss-level `timeline` buckets into one ranked row per guild.
    func standings(regionSlug: String = "world") -> [GuildStanding] {
        let steps = timeline(regionSlug: regionSlug)
        guard !steps.isEmpty else { return [] }

        return bestProgressPerGuild(steps).values
            .map { GuildStanding(guild: $0.guild, bossesDown: $0.progress, lastKillAt: $0.killedAt, isLive: $0.isLive, currentPull: nil) }
            .sorted { lhs, rhs in
                if lhs.bossesDown != rhs.bossesDown { return lhs.bossesDown > rhs.bossesDown }
                switch (lhs.lastKillAt, rhs.lastKillAt) {
                case let (l?, r?): return l < r
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }

    /// Flattens the same timeline buckets into one event per guild-kill, newest first —
    /// a global kill feed across every guild instead of one row per guild's current standing.
    ///
    /// Assumes progress level N was boss N in encounter order (mythic progression in this
    /// raid is gated, so guilds kill bosses in a fixed order) — the API only tells us a
    /// guild reached progress N at time T, not which specific encounter that was.
    func killFeedEvents(regionSlug: String = "world") -> [KillFeedEvent] {
        let steps = timeline(regionSlug: regionSlug)
        guard !steps.isEmpty else { return [] }
        let orderedEncounters = raid.encounters.sorted { $0.ordinal < $1.ordinal }

        var events: [KillFeedEvent] = []
        for step in steps {
            guard step.progress >= 1, step.progress <= orderedEncounters.count else { continue }
            let boss = orderedEncounters[step.progress - 1]

            // The API's array order isn't guaranteed to be chronological, so rank by
            // defeatedAt ourselves rather than trusting array position.
            let kills = step.guilds
                .compactMap { kill in kill.defeatedAt.map { (kill.guild, $0) } }
                .sorted { $0.1 < $1.1 }

            for (index, entry) in kills.enumerated() {
                events.append(KillFeedEvent(guild: entry.0, boss: boss, rank: index + 1, defeatedAt: entry.1))
            }
        }
        return events.sorted { $0.defeatedAt > $1.defeatedAt }
    }

}

// MARK: - Deriving the per-boss summary list from official raid rankings

extension RaidInfo {
    /// One row per boss, in raid order: whichever guild claimed World First (the earliest
    /// kill across every tracked guild), and — for bosses nobody's killed yet — whichever
    /// guild currently has the best (lowest remaining health%) live pull. Pull data comes
    /// from raider.io's own Desktop App combat-log tracking, not WarcraftLogs, so it updates
    /// in near real time during the race.
    func bossSummaries(rankings: [RaidRankingEntry]) -> [BossSummary] {
        var worldFirstBySlug: [String: BossSummary.WorldFirst] = [:]
        var bestPullBySlug: [String: BossSummary.BestPull] = [:]

        for entry in rankings {
            for defeat in entry.encountersDefeated {
                let current = worldFirstBySlug[defeat.slug]
                if current == nil || defeat.firstDefeated < current!.at {
                    worldFirstBySlug[defeat.slug] = BossSummary.WorldFirst(guild: entry.guild, at: defeat.firstDefeated)
                }
            }
            for pull in entry.encountersPulled where !pull.isDefeated {
                guard let percent = pull.bestPercent, let pullCount = pull.numPulls else { continue }
                let current = bestPullBySlug[pull.slug]
                if current == nil || percent < current!.percent {
                    bestPullBySlug[pull.slug] = BossSummary.BestPull(guild: entry.guild, percent: percent, pullCount: pullCount)
                }
            }
        }

        return encounters
            .sorted { $0.ordinal < $1.ordinal }
            .map { boss in BossSummary(boss: boss, worldFirst: worldFirstBySlug[boss.slug], bestPull: bestPullBySlug[boss.slug]) }
    }

    /// For each guild, their live pull data (best %, pull count) on whichever boss comes right
    /// after `bossesDownByGuildId`'s progress for them — keyed by guild id, and absent for a
    /// guild that's killed every boss already or hasn't logged a pull on their next boss yet.
    func currentPulls(bossesDownByGuildId: [Int: Int], rankings: [RaidRankingEntry]) -> [Int: GuildStanding.CurrentPull] {
        let orderedEncounters = encounters.sorted { $0.ordinal < $1.ordinal }

        var result: [Int: GuildStanding.CurrentPull] = [:]
        for entry in rankings {
            guard let bossesDown = bossesDownByGuildId[entry.guild.id], bossesDown < orderedEncounters.count else { continue }
            let nextBoss = orderedEncounters[bossesDown]
            guard let pull = entry.encountersPulled.first(where: { $0.slug == nextBoss.slug && !$0.isDefeated }),
                  let percent = pull.bestPercent, let pullCount = pull.numPulls else { continue }
            result[entry.guild.id] = GuildStanding.CurrentPull(boss: nextBoss, percent: percent, pullCount: pullCount)
        }
        return result
    }

    /// Every guild's best pull on a boss they personally haven't killed yet, across the whole
    /// raid (not just each boss's single frontrunner) — sorted closest-to-a-kill first, and
    /// limited to genuinely close calls (under `maxPercent` remaining health) rather than
    /// every pull on record. Deliberately per-guild rather than globally-unclaimed-only: a
    /// guild's own progress toward their first kill of a boss is still worth showing here even
    /// after another guild has already claimed World First on it — only the push notification
    /// (see push-service's checkHeartbreaks) is scoped down to genuine title-race close calls.
    /// This is only possible because raid-rankings carries live percent data for every
    /// encounter a guild has attempted, not just their current one.
    func closeCalls(rankings: [RaidRankingEntry], maxPercent: Double = 10) -> [CloseCall] {
        let encounterBySlug = Dictionary(uniqueKeysWithValues: encounters.map { ($0.slug, $0) })

        var calls: [CloseCall] = []
        for entry in rankings {
            for pull in entry.encountersPulled where !pull.isDefeated {
                guard let percent = pull.bestPercent, percent < maxPercent,
                      let pullCount = pull.numPulls,
                      let boss = encounterBySlug[pull.slug] else { continue }
                calls.append(CloseCall(guild: entry.guild, boss: boss, percent: percent, pullCount: pullCount))
            }
        }
        return calls.sorted { $0.percent < $1.percent }
    }
}

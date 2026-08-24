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

    private struct UnrankedStanding {
        let guild: RaceGuild
        let bossesDown: Int
        let lastKillAt: Date?
        let isLive: Bool
    }

    /// One ranked row per guild, using raid-rankings (raider.io's live Desktop App pull
    /// tracking) as the source of truth for boss count and kill time — raid-race's own
    /// `timeline` has been observed to omit guilds entirely for extended stretches of the race
    /// (confirmed against raider.io's own public leaderboard: 9 guilds sitting at 2/8 there,
    /// while the timeline only carried 6 guilds total across every progress level), so it can't
    /// be trusted as the primary source anymore. The timeline is still consulted for `isLive`
    /// (streamer status), which raid-rankings doesn't carry, and for any guild raid-rankings
    /// itself doesn't have data for (falls back to the timeline's own, laggier count rather
    /// than dropping the guild). Returns the full list (raid-rankings itself only ever returns
    /// the top 50) — capping/pinning to a subset is a display concern the caller handles.
    func standings(rankings: [RaidRankingEntry], regionSlug: String = "world") -> [GuildStanding] {
        let timelineBest = bestProgressPerGuild(timeline(regionSlug: regionSlug))

        var byGuildId: [Int: UnrankedStanding] = [:]
        for entry in rankings {
            let bossesDown = entry.encountersDefeated.count
            guard bossesDown > 0 else { continue }
            let lastKillAt = entry.encountersDefeated.map(\.firstDefeated).max()
            let isLive = timelineBest[entry.guild.id]?.isLive ?? false
            byGuildId[entry.guild.id] = UnrankedStanding(
                guild: entry.guild, bossesDown: bossesDown, lastKillAt: lastKillAt, isLive: isLive
            )
        }
        for best in timelineBest.values where byGuildId[best.guild.id] == nil {
            byGuildId[best.guild.id] = UnrankedStanding(
                guild: best.guild, bossesDown: best.progress, lastKillAt: best.killedAt, isLive: best.isLive
            )
        }

        let sorted = byGuildId.values.sorted { lhs, rhs in
            if lhs.bossesDown != rhs.bossesDown { return lhs.bossesDown > rhs.bossesDown }
            switch (lhs.lastKillAt, rhs.lastKillAt) {
            case let (l?, r?): return l < r
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        return sorted.enumerated().map { index, entry in
            GuildStanding(
                guild: entry.guild, rank: index + 1, bossesDown: entry.bossesDown,
                lastKillAt: entry.lastKillAt, isLive: entry.isLive
            )
        }
    }

    /// One group per boss with at least one kill, sourced from raid-rankings rather than the
    /// timeline (see `standings(rankings:)` above for why: raid-race's own timeline has been
    /// observed missing guilds entirely for extended stretches of the race). Each
    /// `encountersDefeated` entry already carries its own boss slug and kill timestamp
    /// directly, so unlike the old flat/timeline-based version, this doesn't need to assume
    /// progress level N was boss N in encounter order.
    ///
    /// Each group is capped to its boss's top `maxRank` kills — once a boss has been cleared by
    /// dozens of guilds, "50th place" entries add noise without being notable to anyone. Ranks
    /// are still computed against the full kill list before the cutoff, so "5th" here always
    /// means genuinely 5th, not 5th-among-only-the-kept-kills. Groups are ordered by their most
    /// recent kill, so whichever boss has the freshest action surfaces first.
    func killFeedGroups(rankings: [RaidRankingEntry], maxRank: Int = 5) -> [BossKillGroup] {
        let encounterBySlug = Dictionary(uniqueKeysWithValues: raid.encounters.map { ($0.slug, $0) })

        var killsBySlug: [String: [(guild: RaceGuild, defeatedAt: Date)]] = [:]
        for entry in rankings {
            for defeat in entry.encountersDefeated {
                killsBySlug[defeat.slug, default: []].append((entry.guild, defeat.firstDefeated))
            }
        }

        var groups: [BossKillGroup] = []
        for (slug, kills) in killsBySlug {
            guard let boss = encounterBySlug[slug] else { continue }
            let ranked = kills.sorted { $0.defeatedAt < $1.defeatedAt }
                .prefix(maxRank)
                .enumerated()
                .map { index, kill in
                    KillFeedEvent(guild: kill.guild, boss: boss, rank: index + 1, defeatedAt: kill.defeatedAt)
                }
            guard !ranked.isEmpty else { continue }
            groups.append(BossKillGroup(boss: boss, kills: ranked))
        }
        return groups.sorted { $0.mostRecentKillAt > $1.mostRecentKillAt }
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

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

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RaiderIOError.badResponse
        }
    }
}

// MARK: - Deriving per-guild standings from the timeline buckets

extension WorldFirstTracker {
    /// Flattens the per-boss-level `timeline` buckets into one ranked row per guild.
    func standings(regionSlug: String = "world") -> [GuildStanding] {
        guard let timeline = timelines.first(where: { $0.region.slug == regionSlug })?.timeline
                ?? timelines.first?.timeline else {
            return []
        }

        var best: [Int: (guild: RaceGuild, progress: Int, killedAt: Date?, isLive: Bool)] = [:]

        for step in timeline {
            for kill in step.guilds {
                let current = best[kill.guild.id]
                if current == nil || step.progress > current!.progress {
                    best[kill.guild.id] = (kill.guild, step.progress, kill.defeatedAt, kill.streamers.count > 0)
                }
            }
        }

        return best.values
            .map { GuildStanding(guild: $0.guild, bossesDown: $0.progress, lastKillAt: $0.killedAt, isLive: $0.isLive) }
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
        guard let timeline = timelines.first(where: { $0.region.slug == regionSlug })?.timeline
                ?? timelines.first?.timeline else {
            return []
        }
        let orderedEncounters = raid.encounters.sorted { $0.ordinal < $1.ordinal }

        var events: [KillFeedEvent] = []
        for step in timeline {
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

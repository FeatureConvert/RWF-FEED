//
//  Models.swift
//  RWF FEED
//
//  Data models for the raider.io RWF global coverage feed and boss progress tracker.
//

import Foundation

// MARK: - Feed (live coverage thread)

struct ThreadListResponse: Decodable {
    let thread: ThreadInfo
    let posts: [FeedPost]
}

struct ThreadInfo: Decodable {
    let id: Int
    let slug: String
    let subject: String
}

struct FeedPost: Decodable, Identifiable, Equatable {
    let id: Int
    let content: String?
    let contentPreview: String?
    let author: String?
    let authorAvatar: String?
    let tags: [FeedTag]
    let publishedAt: Date
    let isPriority: Bool
    let deletedAt: Date?

    /// Deleted posts come back from the API with only id/published_at/deleted_at — everything
    /// else is simply absent from the JSON, not null.
    var isDeleted: Bool { deletedAt != nil || content == nil }

    enum CodingKeys: String, CodingKey {
        case id, content, contentPreview, author, authorAvatar, tags
        case publishedAt = "published_at"
        case isPriority = "is_priority"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        contentPreview = try container.decodeIfPresent(String.self, forKey: .contentPreview)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        authorAvatar = try container.decodeIfPresent(String.self, forKey: .authorAvatar)
        tags = try container.decodeIfPresent([FeedTag].self, forKey: .tags) ?? []
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
        isPriority = try container.decodeIfPresent(Bool.self, forKey: .isPriority) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    static func == (lhs: FeedPost, rhs: FeedPost) -> Bool {
        lhs.id == rhs.id
    }
}

struct FeedTag: Decodable, Identifiable, Equatable {
    let slug: String
    let name: String
    let category: String

    var id: String { slug }
}

// MARK: - Boss progress tracker (raid-race)

struct RaidRaceResponse: Decodable {
    let worldFirstTracker: WorldFirstTracker
}

struct WorldFirstTracker: Decodable {
    let timelines: [RegionTimeline]
    let raid: RaidInfo
}

struct RegionTimeline: Decodable {
    let region: RegionRef
    let timeline: [ProgressStep]
}

struct RegionRef: Decodable {
    let name: String
    let slug: String
    let shortName: String

    enum CodingKeys: String, CodingKey {
        case name, slug
        case shortName = "short_name"
    }
}

struct ProgressStep: Decodable {
    let progress: Int
    let totalGuilds: Int
    let guilds: [GuildKill]
}

struct GuildKill: Decodable {
    let defeatedAt: Date?
    let guild: RaceGuild
    let streamers: StreamerInfo
}

struct StreamerInfo: Decodable {
    let count: Int
}

struct RaceGuild: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let displayName: String
    let faction: String
    let realm: RealmRef
    let region: RegionRef
    let path: String
    let logo: String
    let color: String?

    static func == (lhs: RaceGuild, rhs: RaceGuild) -> Bool {
        lhs.id == rhs.id
    }
}

struct RealmRef: Decodable {
    let name: String
}

struct RaidInfo: Decodable {
    let name: String
    let shortName: String
    let encounters: [Encounter]

    enum CodingKeys: String, CodingKey {
        case name
        case shortName = "short_name"
        case encounters
    }
}

struct Encounter: Decodable, Identifiable {
    let encounterId: Int
    let name: String
    let slug: String
    let ordinal: Int
    let iconUrl: String

    var id: Int { encounterId }

    /// `iconUrl` comes back as a host-relative path (e.g. "/images/wow/icons/large/...jpg").
    var fullIconURL: URL? { URL(string: "https://cdn.raiderio.net\(iconUrl)") }
}

// MARK: - Derived guild standing (one row per guild in the tracker)

struct GuildStanding: Identifiable {
    let guild: RaceGuild
    let bossesDown: Int
    let lastKillAt: Date?
    let isLive: Bool

    var id: Int { guild.id }
}

// MARK: - Derived kill-feed event (one row per boss kill, across every guild)

struct KillFeedEvent: Identifiable {
    let guild: RaceGuild
    let boss: Encounter
    /// 1 = world first, 2 = second guild to down it, etc. — this guild's placement among
    /// every guild that killed this specific boss, by kill time.
    let rank: Int
    let defeatedAt: Date

    var id: String { "\(guild.id)-\(boss.id)" }

    var rankLabel: String {
        if rank == 1 { return "World First" }
        let tens = rank % 100
        if (11...13).contains(tens) { return "\(rank)th" }
        switch rank % 10 {
        case 1: return "\(rank)st"
        case 2: return "\(rank)nd"
        case 3: return "\(rank)rd"
        default: return "\(rank)th"
        }
    }
}

// MARK: - Derived boss-kill group (one section per boss, in the Kills tab)

struct BossKillGroup: Identifiable {
    let boss: Encounter
    /// Rank-ascending (World First first), already capped to the top N by the caller.
    let kills: [KillFeedEvent]

    var id: Int { boss.id }
    /// The most recent kill among the (already-capped) kills shown — used to order groups so
    /// whichever boss has the freshest action surfaces first.
    var mostRecentKillAt: Date { kills.last?.defeatedAt ?? .distantPast }
}

// MARK: - Official raid rankings (raider.io's own live pull tracking, from the Desktop App)

struct RaidRankingsResponse: Decodable {
    let raidRankings: [RaidRankingEntry]
}

struct RaidRankingEntry: Decodable {
    let guild: RaceGuild
    let encountersDefeated: [EncounterDefeatEntry]
    let encountersPulled: [EncounterPullEntry]
}

struct EncounterDefeatEntry: Decodable {
    let slug: String
    let firstDefeated: Date
}

struct EncounterPullEntry: Decodable {
    let slug: String
    /// Absent for some already-defeated encounters rather than 0 — genuinely unknown, not zero.
    let numPulls: Int?
    /// 0–100 scale (e.g. 63.01), unlike some of raider.io's other endpoints which use a 0–1
    /// fraction. Absent alongside numPulls in the same cases.
    let bestPercent: Double?
    let isDefeated: Bool
}

// MARK: - Hall of fame (world-first kill VODs)

struct HallOfFameResponse: Decodable {
    let hallOfFame: HallOfFame
}

struct HallOfFame: Decodable {
    let bossKills: [HallOfFameBossKill]
}

struct HallOfFameBossKill: Decodable {
    let boss: Encounter?
    let bossKillVideo: [BossKillVideo]?
}

struct BossKillVideo: Decodable {
    let type: String
    let id: String
    let videoTimestampSeconds: Int

    /// Only Twitch VODs are documented on this endpoint; nil for anything else so callers
    /// don't have to know the URL scheme for a video type raider.io might add later.
    var twitchURL: URL? {
        guard type == "twitch" else { return nil }
        let hours = videoTimestampSeconds / 3600
        let minutes = (videoTimestampSeconds % 3600) / 60
        let seconds = videoTimestampSeconds % 60
        return URL(string: "https://www.twitch.tv/videos/\(id)?t=\(hours)h\(minutes)m\(seconds)s")
    }
}

// MARK: - Derived per-boss summary (one row per boss, in raid order)

struct BossSummary: Identifiable {
    struct WorldFirst {
        let guild: RaceGuild
        let at: Date
        /// Deep-links to the moment of the kill, when raider.io's Hall of Fame has a VOD for
        /// it — absent for older kills or when nobody was streaming.
        var vodURL: URL? = nil
    }
    struct BestPull {
        let guild: RaceGuild
        let percent: Double
        let pullCount: Int
    }

    let boss: Encounter
    let worldFirst: WorldFirst?
    let bestPull: BestPull?

    var id: Int { boss.id }
}

// MARK: - Derived close call (one entry per guild's best not-yet-killed pull, across every boss)

struct CloseCall: Identifiable {
    let guild: RaceGuild
    let boss: Encounter
    let percent: Double
    let pullCount: Int

    var id: String { "\(guild.id)-\(boss.id)" }
}

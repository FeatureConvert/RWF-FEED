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
    let ordinal: Int
    let iconUrl: String

    var id: Int { encounterId }
}

// MARK: - Derived guild standing (one row per guild in the tracker)

struct GuildStanding: Identifiable {
    let guild: RaceGuild
    let bossesDown: Int
    let lastKillAt: Date?
    let isLive: Bool

    var id: Int { guild.id }
}

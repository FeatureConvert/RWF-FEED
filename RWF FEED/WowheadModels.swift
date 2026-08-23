//
//  WowheadModels.swift
//  RWF FEED
//
//  A WoW retail news article, parsed from Wowhead's public RSS feed (see
//  WowheadFeedParser). Not a raider.io type since it comes from a different source.
//

import Foundation

struct WowheadArticle: Identifiable, Equatable {
    let guid: String
    let title: String
    let link: URL
    let summary: String
    let imageURL: URL?
    let publishedAt: Date

    var id: String { guid }

    static func == (lhs: WowheadArticle, rhs: WowheadArticle) -> Bool {
        lhs.guid == rhs.guid
    }
}

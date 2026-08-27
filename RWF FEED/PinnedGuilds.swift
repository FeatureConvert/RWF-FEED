//
//  PinnedGuilds.swift
//  RWF FEED
//
//  User-chosen guilds pinned to the top of the Tracker tab, keyed by raider.io guild id.
//  Purely a local display preference — no server/push involvement. Per-guild push filtering
//  was tried before (see push-service/src/worker.js's device-storage comment) and removed
//  for reliability; this is a much simpler, UI-only "float to the top" feature.
//

import Foundation
import Combine

@MainActor
final class PinnedGuilds: ObservableObject {
    static let shared = PinnedGuilds()

    private static let key = "PinnedGuilds.guildIDs"

    @Published private(set) var guildIDs: Set<Int> {
        didSet { UserDefaults.standard.set(Array(guildIDs), forKey: Self.key) }
    }

    private init() {
        let stored = UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? []
        guildIDs = Set(stored)
    }

    func isPinned(_ guildId: Int) -> Bool {
        guildIDs.contains(guildId)
    }

    func toggle(_ guildId: Int) {
        if guildIDs.contains(guildId) {
            guildIDs.remove(guildId)
        } else {
            guildIDs.insert(guildId)
        }
    }
}

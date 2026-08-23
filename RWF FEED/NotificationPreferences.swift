//
//  NotificationPreferences.swift
//  RWF FEED
//
//  Persists the user's choice between "notify me about every feed post" (the default) and
//  "notify me only when this specific guild kills a boss". Changing it re-registers the
//  device token with the push-service Worker so the new preference takes effect immediately.
//

import Foundation
import Combine

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    private static let guildIDKey = "NotificationPreferences.favoriteGuildID"
    private static let guildNameKey = "NotificationPreferences.favoriteGuildName"

    @Published private(set) var favoriteGuildID: Int?
    @Published private(set) var favoriteGuildName: String?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.guildIDKey) != nil {
            favoriteGuildID = defaults.integer(forKey: Self.guildIDKey)
            favoriteGuildName = defaults.string(forKey: Self.guildNameKey)
        }
    }

    /// Pass nil to go back to "every feed post".
    func setFavoriteGuild(id: Int?, name: String?) {
        favoriteGuildID = id
        favoriteGuildName = name

        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id, forKey: Self.guildIDKey)
            defaults.set(name, forKey: Self.guildNameKey)
        } else {
            defaults.removeObject(forKey: Self.guildIDKey)
            defaults.removeObject(forKey: Self.guildNameKey)
        }

        PushRegistration.updateGuildPreference(guildId: id)
    }
}

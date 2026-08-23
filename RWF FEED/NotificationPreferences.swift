//
//  NotificationPreferences.swift
//  RWF FEED
//
//  Persists the user's choice between "notify me about every feed post" (the default, an
//  empty favorites list) and "notify me only when one of these guilds kills a boss". Changing
//  the list re-registers the device token with the push-service Worker so it takes effect
//  immediately.
//

import Foundation
import Combine

struct FavoriteGuild: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
}

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    private static let favoritesKey = "NotificationPreferences.favoriteGuilds"

    @Published private(set) var favoriteGuilds: [FavoriteGuild] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let decoded = try? JSONDecoder().decode([FavoriteGuild].self, from: data) {
            favoriteGuilds = decoded
        }
    }

    func addFavoriteGuild(id: Int, name: String) {
        guard !favoriteGuilds.contains(where: { $0.id == id }) else { return }
        favoriteGuilds.append(FavoriteGuild(id: id, name: name))
        persist()
    }

    func removeFavoriteGuild(id: Int) {
        favoriteGuilds.removeAll { $0.id == id }
        persist()
    }

    /// Back to "every feed post".
    func clearFavorites() {
        favoriteGuilds = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(favoriteGuilds) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
        PushRegistration.updateFavorites(guildIds: favoriteGuilds.map(\.id))
    }
}

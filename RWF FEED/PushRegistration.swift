//
//  PushRegistration.swift
//  RWF FEED
//
//  Sends this device's APNs token to the push-service Worker so it can notify us about new
//  feed posts (or favorite guilds' kills — see NotificationPreferences) even when the app is
//  closed. See push-service/README.md for how that service is deployed.
//

import Foundation

enum PushRegistration {
    static let registerURL = URL(string: "https://rwf-feed-push.rwf-feed.workers.dev/register")!

    private static let tokenHexKey = "PushRegistration.lastTokenHex"

    private struct RegisterPayload: Encodable {
        let deviceToken: String
        let guildIds: [Int]
    }

    static func register(deviceToken: Data) {
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(tokenHex, forKey: tokenHexKey)
        send(tokenHex: tokenHex, guildIds: NotificationPreferences.shared.favoriteGuilds.map(\.id))
    }

    /// Re-sends the current device token with the updated favorite-guild list — called
    /// whenever the user changes their notification preferences. No-ops if we've never
    /// registered for remote notifications yet (nothing to re-send).
    static func updateFavorites(guildIds: [Int]) {
        guard let tokenHex = UserDefaults.standard.string(forKey: tokenHexKey) else { return }
        send(tokenHex: tokenHex, guildIds: guildIds)
    }

    private static func send(tokenHex: String, guildIds: [Int]) {
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RegisterPayload(deviceToken: tokenHex, guildIds: guildIds))

        Task {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                NSLog("PushRegistration: failed to register device token: %@", String(describing: error))
            }
        }
    }
}

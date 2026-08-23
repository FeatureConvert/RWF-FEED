//
//  PushRegistration.swift
//  RWF FEED
//
//  Sends this device's APNs token to the push-service Worker so it can notify us about new
//  feed posts (or a specific favorite guild's kills — see NotificationPreferences) even when
//  the app is closed. See push-service/README.md for how that service is deployed.
//

import Foundation

enum PushRegistration {
    static let registerURL = URL(string: "https://rwf-feed-push.rwf-feed.workers.dev/register")!

    private static let tokenHexKey = "PushRegistration.lastTokenHex"

    private struct RegisterPayload: Encodable {
        let deviceToken: String
        let guildId: Int?
    }

    static func register(deviceToken: Data) {
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(tokenHex, forKey: tokenHexKey)
        send(tokenHex: tokenHex, guildId: NotificationPreferences.shared.favoriteGuildID)
    }

    /// Re-sends the current device token with an updated guildId — called when the user
    /// changes their notification preference in Settings. No-ops if we've never registered
    /// for remote notifications yet (nothing to re-send).
    static func updateGuildPreference(guildId: Int?) {
        guard let tokenHex = UserDefaults.standard.string(forKey: tokenHexKey) else { return }
        send(tokenHex: tokenHex, guildId: guildId)
    }

    private static func send(tokenHex: String, guildId: Int?) {
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RegisterPayload(deviceToken: tokenHex, guildId: guildId))

        Task {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                NSLog("PushRegistration: failed to register device token: %@", String(describing: error))
            }
        }
    }
}

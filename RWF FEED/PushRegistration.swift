//
//  PushRegistration.swift
//  RWF FEED
//
//  Sends this device's APNs token to the push-service Worker so it can notify us about new
//  feed posts even when the app is closed. See push-service/README.md for how that service
//  is deployed.
//

import Foundation

enum PushRegistration {
    static let registerURL = URL(string: "https://rwf-feed-push.rwf-feed.workers.dev/register")!
    private static let lastTokenKey = "PushRegistration.lastDeviceTokenHex"

    private struct RegisterPayload: Encodable {
        let deviceToken: String
        let raiderioEnabled: Bool
        let wowheadEnabled: Bool
        let spoilerFreeEnabled: Bool
        let heartbreakThresholdPercent: Double
        let notifyNonWorldFirstHeartbreaks: Bool
    }

    static func register(deviceToken: Data) {
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(tokenHex, forKey: lastTokenKey)
        send(tokenHex: tokenHex)
    }

    /// Called when a Settings toggle changes — re-sends the cached device token with updated
    /// preferences so the Worker can filter server-side. No-ops before the app has ever
    /// received a token; the next real registration will carry whatever prefs are current.
    static func updatePreferences() {
        guard let tokenHex = UserDefaults.standard.string(forKey: lastTokenKey) else { return }
        send(tokenHex: tokenHex)
    }

    private static func send(tokenHex: String) {
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = RegisterPayload(
            deviceToken: tokenHex,
            raiderioEnabled: NotificationPreferences.shared.raiderioEnabled,
            wowheadEnabled: NotificationPreferences.shared.wowheadEnabled,
            spoilerFreeEnabled: NotificationPreferences.shared.spoilerFreeEnabled,
            heartbreakThresholdPercent: NotificationPreferences.shared.heartbreakThresholdPercent,
            notifyNonWorldFirstHeartbreaks: NotificationPreferences.shared.notifyNonWorldFirstHeartbreaks
        )
        request.httpBody = try? JSONEncoder().encode(payload)

        Task {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                NSLog("PushRegistration: failed to register device token: %@", String(describing: error))
            }
        }
    }
}

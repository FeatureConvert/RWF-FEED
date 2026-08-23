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

    private struct RegisterPayload: Encodable {
        let deviceToken: String
    }

    static func register(deviceToken: Data) {
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RegisterPayload(deviceToken: tokenHex))

        Task {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                NSLog("PushRegistration: failed to register device token: %@", String(describing: error))
            }
        }
    }
}

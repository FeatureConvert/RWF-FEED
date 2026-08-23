//
//  NotificationPreferences.swift
//  RWF FEED
//
//  Two independent on/off switches — Raider.IO pushes (new feed posts, Major Heartbreaker)
//  and Wowhead news pushes — surfaced in Settings. Both default on. Toggling either re-sends
//  this device's token to the push-service Worker so it can filter server-side; the client
//  can't filter a push after APNs has already delivered it while the app is closed.
//

import Foundation
import Combine

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    private static let raiderioKey = "NotificationPreferences.raiderioEnabled"
    private static let wowheadKey = "NotificationPreferences.wowheadEnabled"

    @Published var raiderioEnabled: Bool {
        didSet {
            guard oldValue != raiderioEnabled else { return }
            UserDefaults.standard.set(raiderioEnabled, forKey: Self.raiderioKey)
            PushRegistration.updatePreferences()
        }
    }

    @Published var wowheadEnabled: Bool {
        didSet {
            guard oldValue != wowheadEnabled else { return }
            UserDefaults.standard.set(wowheadEnabled, forKey: Self.wowheadKey)
            PushRegistration.updatePreferences()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        raiderioEnabled = (defaults.object(forKey: Self.raiderioKey) as? Bool) ?? true
        wowheadEnabled = (defaults.object(forKey: Self.wowheadKey) as? Bool) ?? true
    }
}

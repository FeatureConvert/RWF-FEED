//
//  NotificationPreferences.swift
//  RWF FEED
//
//  Three independent switches surfaced in Settings — Raider.IO pushes (new feed posts, Major
//  Heartbreaker, World First kills), Wowhead news pushes, and spoiler-free mode (redacts World
//  First kill pushes to a generic "Spoiler Alert" instead of naming the guild/boss). The first
//  two default on; spoiler-free defaults off. Toggling any of them re-sends this device's
//  token to the push-service Worker so it can filter/redact server-side — the client can't
//  filter or rewrite a push after APNs has already delivered it while the app is closed.
//

import Foundation
import Combine

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    private static let raiderioKey = "NotificationPreferences.raiderioEnabled"
    private static let wowheadKey = "NotificationPreferences.wowheadEnabled"
    private static let spoilerFreeKey = "NotificationPreferences.spoilerFreeEnabled"

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

    @Published var spoilerFreeEnabled: Bool {
        didSet {
            guard oldValue != spoilerFreeEnabled else { return }
            UserDefaults.standard.set(spoilerFreeEnabled, forKey: Self.spoilerFreeKey)
            PushRegistration.updatePreferences()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        raiderioEnabled = (defaults.object(forKey: Self.raiderioKey) as? Bool) ?? true
        wowheadEnabled = (defaults.object(forKey: Self.wowheadKey) as? Bool) ?? true
        spoilerFreeEnabled = (defaults.object(forKey: Self.spoilerFreeKey) as? Bool) ?? false
    }
}

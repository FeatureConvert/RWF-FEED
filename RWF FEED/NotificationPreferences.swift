//
//  NotificationPreferences.swift
//  RWF FEED
//
//  Notification preferences surfaced in Settings — Raider.IO pushes (new feed posts, Major
//  Heartbreaker, World First kills), Wowhead news pushes, spoiler-free mode (redacts World
//  First kill pushes to a generic "Spoiler Alert" instead of naming the guild/boss), the
//  close-call health% threshold Major Heartbreaker pushes at, and whether that push should
//  also fire for a guild's close call on a boss another guild has already claimed (not just
//  genuine title-race close calls). raiderioEnabled/wowheadEnabled default on; the rest
//  default off/to the standard threshold. Toggling any of them re-sends this device's token
//  to the push-service Worker so it can filter/redact/threshold server-side — the client
//  can't filter or rewrite a push after APNs has already delivered it while the app is
//  closed.
//

import Foundation
import Combine

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    static let defaultHeartbreakThresholdPercent: Double = 5.01

    private static let raiderioKey = "NotificationPreferences.raiderioEnabled"
    private static let wowheadKey = "NotificationPreferences.wowheadEnabled"
    private static let spoilerFreeKey = "NotificationPreferences.spoilerFreeEnabled"
    private static let heartbreakThresholdKey = "NotificationPreferences.heartbreakThresholdPercent"
    private static let notifyNonWorldFirstKey = "NotificationPreferences.notifyNonWorldFirstHeartbreaks"

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

    /// Remaining boss health%, below which a new-record close call triggers a Major
    /// Heartbreaker push. 1...25, matching the Worker's default of 5.01.
    @Published var heartbreakThresholdPercent: Double {
        didSet {
            guard oldValue != heartbreakThresholdPercent else { return }
            UserDefaults.standard.set(heartbreakThresholdPercent, forKey: Self.heartbreakThresholdKey)
            PushRegistration.updatePreferences()
        }
    }

    /// When true, Major Heartbreaker also pushes for a guild's close call on a boss another
    /// guild has already claimed — not just close calls that are still part of the title
    /// race. Off by default, matching the push's original world-first-only scope.
    @Published var notifyNonWorldFirstHeartbreaks: Bool {
        didSet {
            guard oldValue != notifyNonWorldFirstHeartbreaks else { return }
            UserDefaults.standard.set(notifyNonWorldFirstHeartbreaks, forKey: Self.notifyNonWorldFirstKey)
            PushRegistration.updatePreferences()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        raiderioEnabled = (defaults.object(forKey: Self.raiderioKey) as? Bool) ?? true
        wowheadEnabled = (defaults.object(forKey: Self.wowheadKey) as? Bool) ?? true
        spoilerFreeEnabled = (defaults.object(forKey: Self.spoilerFreeKey) as? Bool) ?? false
        heartbreakThresholdPercent =
            (defaults.object(forKey: Self.heartbreakThresholdKey) as? Double) ?? Self.defaultHeartbreakThresholdPercent
        notifyNonWorldFirstHeartbreaks = (defaults.object(forKey: Self.notifyNonWorldFirstKey) as? Bool) ?? false
    }
}

//
//  NotificationPreferences.swift
//  RWF FEED
//
//  Notification preferences surfaced in Settings — three independent Raider.IO-sourced pushes
//  (new feed posts, Major Heartbreaker close calls, World First kills — previously one combined
//  "Raider.IO Updates" toggle, split out so a user can e.g. keep World First kills without the
//  chattier Heartbreak close-call pushes), Wowhead news pushes, spoiler-free mode (redacts World
//  First kill pushes to a generic "Spoiler Alert" instead of naming the guild/boss), the
//  close-call health% threshold Major Heartbreaker pushes at, and whether that push should
//  also fire for a guild's close call on a boss another guild has already claimed (not just
//  genuine title-race close calls). feedPostsEnabled/majorHeartbreakerEnabled/
//  worldFirstKillEnabled/wowheadEnabled default on; the rest default off/to the standard
//  threshold. Toggling any of them re-sends this device's token to the push-service Worker so
//  it can filter/redact/threshold server-side — the client can't filter or rewrite a push after
//  APNs has already delivered it while the app is closed.
//

import Foundation
import Combine

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    /// Lands exactly on the Settings slider's 0.5-step grid — an off-grid default (e.g. 5.01)
    /// would silently snap to the nearest step the instant a user first touches the slider,
    /// changing their stored preference without any interaction they'd recognize as "changing" it.
    static let defaultHeartbreakThresholdPercent: Double = 5.0

    /// Pre-split single toggle ("Raider.IO Updates") this device may still have persisted —
    /// read once, at init, purely to seed the three split preferences below for anyone
    /// updating from a build that only had this one. Never written to again after that.
    private static let legacyRaiderioKey = "NotificationPreferences.raiderioEnabled"
    private static let feedPostsKey = "NotificationPreferences.feedPostsEnabled"
    private static let majorHeartbreakerKey = "NotificationPreferences.majorHeartbreakerEnabled"
    private static let worldFirstKillKey = "NotificationPreferences.worldFirstKillEnabled"
    private static let wowheadKey = "NotificationPreferences.wowheadEnabled"
    private static let spoilerFreeKey = "NotificationPreferences.spoilerFreeEnabled"
    private static let heartbreakThresholdKey = "NotificationPreferences.heartbreakThresholdPercent"
    private static let notifyNonWorldFirstKey = "NotificationPreferences.notifyNonWorldFirstHeartbreaks"

    @Published var feedPostsEnabled: Bool {
        didSet {
            guard oldValue != feedPostsEnabled else { return }
            UserDefaults.standard.set(feedPostsEnabled, forKey: Self.feedPostsKey)
            PushRegistration.updatePreferences()
        }
    }

    @Published var majorHeartbreakerEnabled: Bool {
        didSet {
            guard oldValue != majorHeartbreakerEnabled else { return }
            UserDefaults.standard.set(majorHeartbreakerEnabled, forKey: Self.majorHeartbreakerKey)
            PushRegistration.updatePreferences()
        }
    }

    @Published var worldFirstKillEnabled: Bool {
        didSet {
            guard oldValue != worldFirstKillEnabled else { return }
            UserDefaults.standard.set(worldFirstKillEnabled, forKey: Self.worldFirstKillKey)
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
        // A device that never had the combined toggle (fresh install) has no legacy value to
        // migrate, so this is nil and each split preference falls back to its own `true`
        // default below — same as the combined toggle's own former default.
        let legacyRaiderio = defaults.object(forKey: Self.legacyRaiderioKey) as? Bool
        feedPostsEnabled = (defaults.object(forKey: Self.feedPostsKey) as? Bool) ?? legacyRaiderio ?? true
        majorHeartbreakerEnabled = (defaults.object(forKey: Self.majorHeartbreakerKey) as? Bool) ?? legacyRaiderio ?? true
        worldFirstKillEnabled = (defaults.object(forKey: Self.worldFirstKillKey) as? Bool) ?? legacyRaiderio ?? true
        wowheadEnabled = (defaults.object(forKey: Self.wowheadKey) as? Bool) ?? true
        spoilerFreeEnabled = (defaults.object(forKey: Self.spoilerFreeKey) as? Bool) ?? false
        heartbreakThresholdPercent =
            (defaults.object(forKey: Self.heartbreakThresholdKey) as? Double) ?? Self.defaultHeartbreakThresholdPercent
        notifyNonWorldFirstHeartbreaks = (defaults.object(forKey: Self.notifyNonWorldFirstKey) as? Bool) ?? false
    }
}

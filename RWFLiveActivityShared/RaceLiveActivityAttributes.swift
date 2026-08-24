//
//  RaceLiveActivityAttributes.swift
//  Shared between the main app (starts/ends the activity, requests the push token) and
//  RWFFeedWidget (renders the Dynamic Island / Lock Screen UI) — ActivityKit requires the
//  exact same ActivityAttributes type on both sides, unlike the Home Screen widget's
//  WidgetBossState, which only the widget extension ever touches.
//

import ActivityKit
import Foundation

struct RaceLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var bossName: String
        var bossOrdinal: Int
        var totalBosses: Int
        /// Raw image bytes, not a URL — the widget extension can't reliably load a network image
        /// on its own (same reason the Home Screen widget pre-fetches icon bytes; see
        /// WidgetData.swift), and Data round-trips through push as base64 automatically.
        var bossIconData: Data?
        var bestGuildName: String?
        var bestPercent: Double?
        var pullCount: Int?
    }

    /// ActivityAttributes requires at least one non-updating property alongside ContentState;
    /// nothing here actually varies over the activity's lifetime.
    var raidName: String
}

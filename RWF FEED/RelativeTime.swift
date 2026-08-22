//
//  RelativeTime.swift
//  RWF FEED
//
//  Short "5m" / "2h" / "just now" style timestamps, matching the raider.io feed style.
//

import Foundation

enum RelativeTime {
    static func short(from date: Date, to now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60:
            return "just now"
        case 60..<3600:
            return "\(seconds / 60)m"
        case 3600..<86400:
            return "\(seconds / 3600)h"
        default:
            return "\(seconds / 86400)d"
        }
    }

    /// "For 17:23:01" style elapsed duration, matching the boss-progress tracker.
    static func elapsed(since date: Date, to now: Date = Date()) -> String {
        let total = max(0, Int(now.timeIntervalSince(date)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

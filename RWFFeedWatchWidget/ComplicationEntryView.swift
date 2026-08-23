//
//  ComplicationEntryView.swift
//  RWFFeedWatchWidget
//
//  Uses the app's purple accent (matching the main app's Theme.accent) via plain
//  .foregroundStyle rather than .widgetAccentable() — the latter opts content into the watch
//  face's own tint system, which overrides it back to monochrome on faces that don't render
//  complications in full color.
//

import WidgetKit
import SwiftUI

private let rwfAccent = Color(red: Double(0x91) / 255, green: Double(0x84) / 255, blue: Double(0xD9) / 255)

struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplication(boss: entry.boss)
        case .accessoryRectangular:
            RectangularComplication(boss: entry.boss)
        case .accessoryInline:
            InlineComplication(boss: entry.boss)
        case .accessoryCorner:
            CornerComplication(boss: entry.boss)
        default:
            InlineComplication(boss: entry.boss)
        }
    }
}

private func percentText(_ percent: Double?) -> String {
    guard let percent else { return "—" }
    return String(format: "%.1f%%", percent)
}

/// "Kill progress" — bestPercent is remaining boss health (lower is closer to a kill), so
/// progress toward the kill is the inverse. Used for the circular ring, where filling up as
/// you approach the kill matches how ring gauges read everywhere else (e.g. Activity rings).
private func killProgress(_ percent: Double?) -> Double {
    guard let percent else { return 0 }
    return max(0, min(100, 100 - percent)) / 100
}

/// Remaining boss health as a fraction, unlike killProgress above — this one is for the
/// rectangular complication's linear bar, which reads as a health bar: full at fight start,
/// draining down (its filled/leading edge receding from right toward left) as the boss takes
/// damage, empty at 0% health. Left = 0% is Gauge's own default fill origin, so no custom
/// drawing is needed — just feed it the health fraction directly instead of the inverted one.
private func healthFraction(_ percent: Double?) -> Double {
    guard let percent else { return 1 }
    return max(0, min(100, percent)) / 100
}

struct CircularComplication: View {
    let boss: WatchBossState?

    var body: some View {
        Gauge(value: killProgress(boss?.bestPercent)) {
            Text("\(boss?.bossOrdinal ?? 0)")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text("\(boss?.bossOrdinal ?? 0)/\(boss?.totalBosses ?? 8)")
                    .font(.system(size: 11, weight: .semibold))
                Text(percentText(boss?.bestPercent))
                    .font(.system(size: 11))
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(rwfAccent)
    }
}

struct RectangularComplication: View {
    let boss: WatchBossState?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BOSS \(boss?.bossOrdinal ?? 0)/\(boss?.totalBosses ?? 8)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(boss?.bossName ?? "RWF Feed")
                .font(.headline)
                .foregroundStyle(rwfAccent)
                .lineLimit(1)

            Gauge(value: healthFraction(boss?.bestPercent)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(rwfAccent)

            if let guild = boss?.bestGuildName {
                Text("\(percentText(boss?.bestPercent)) · \(guild)")
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                Text("No live pulls yet")
                    .font(.caption2)
            }
        }
    }
}

struct InlineComplication: View {
    let boss: WatchBossState?

    var body: some View {
        if let boss, let percent = boss.bestPercent {
            Text("\(boss.bossName) \(percentText(percent))")
        } else if let boss {
            Text("Boss \(boss.bossOrdinal): \(boss.bossName)")
        } else {
            Text("RWF Feed")
        }
    }
}

struct CornerComplication: View {
    let boss: WatchBossState?

    var body: some View {
        Text(percentText(boss?.bestPercent))
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(rwfAccent)
    }
}

#Preview(as: .accessoryRectangular) {
    RWFFeedComplication()
} timeline: {
    ComplicationEntry(date: .now, boss: .placeholder)
}

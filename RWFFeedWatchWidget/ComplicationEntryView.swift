//
//  ComplicationEntryView.swift
//  RWFFeedWatchWidget
//
//  All families here are rendered tinted/monochrome by the system depending on the watch
//  face, so layout and text matter far more than color — no custom colors are applied.
//

import WidgetKit
import SwiftUI

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

struct CircularComplication: View {
    let boss: WatchBossState?

    var body: some View {
        Gauge(value: max(0, min(100, 100 - (boss?.bestPercent ?? 100))), in: 0...100) {
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
    }
}

struct RectangularComplication: View {
    let boss: WatchBossState?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BOSS \(boss?.bossOrdinal ?? 0)/\(boss?.totalBosses ?? 8)")
                .font(.system(size: 10, weight: .bold))
            Text(boss?.bossName ?? "RWF Feed")
                .font(.headline)
                .lineLimit(1)
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
            .widgetLabel {
                Text(boss?.bossName ?? "RWF Feed")
            }
    }
}

#Preview(as: .accessoryCircular) {
    RWFFeedComplication()
} timeline: {
    ComplicationEntry(date: .now, boss: .placeholder)
}

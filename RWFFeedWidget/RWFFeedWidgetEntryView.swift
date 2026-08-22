//
//  RWFFeedWidgetEntryView.swift
//  RWFFeedWidget
//

import WidgetKit
import SwiftUI

struct RWFFeedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RWFTimelineEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineBossView(boss: entry.boss)
        case .accessoryCircular:
            CircularBossView(boss: entry.boss)
        case .accessoryRectangular:
            RectangularBossView(boss: entry.boss)
        case .systemLarge, .systemExtraLarge:
            LargeBossView(boss: entry.boss)
        case .systemSmall:
            SmallBossView(boss: entry.boss)
        default:
            MediumBossView(boss: entry.boss)
        }
    }
}

private func percentText(_ percent: Double?) -> String {
    guard let percent else { return "—" }
    return String(format: "%.1f%%", percent)
}

// MARK: - Home Screen families

struct SmallBossView: View {
    let boss: WidgetBossState?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BOSS \(boss?.bossOrdinal ?? 0)/\(boss?.totalBosses ?? 8)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Spacer()
            }
            BossIcon(data: boss?.iconData, size: 32)
            Text(boss?.bossName ?? "—")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WidgetTheme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(percentText(boss?.bestPercent))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent)
                Text(boss?.bestGuildName ?? "No pulls yet")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

struct MediumBossView: View {
    let boss: WidgetBossState?

    var body: some View {
        HStack(spacing: 12) {
            BossIcon(data: boss?.iconData, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("BOSS \(boss?.bossOrdinal ?? 0)/\(boss?.totalBosses ?? 8)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(boss?.bossName ?? "—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                if let guild = boss?.bestGuildName, let pulls = boss?.pullCount {
                    Text("\(guild) · \(pulls) pulls")
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetTheme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("No live pulls yet")
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Text(percentText(boss?.bestPercent))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(WidgetTheme.accent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }
}

struct LargeBossView: View {
    let boss: WidgetBossState?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BossIcon(data: boss?.iconData, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOSS \(boss?.bossOrdinal ?? 0)/\(boss?.totalBosses ?? 8) · FURTHEST PULLED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WidgetTheme.textSecondary)
                    Text(boss?.bossName ?? "—")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textPrimary)
                }
                Spacer()
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("BEST LIVE PULL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(percentText(boss?.bestPercent))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent)
                    .monospacedDigit()
                if let guild = boss?.bestGuildName, let pulls = boss?.pullCount {
                    Text("\(guild) — \(pulls) pulls")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textPrimary)
                } else {
                    Text("No live pulls yet")
                        .font(.system(size: 14))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }
}

// MARK: - Lock Screen / StandBy accessory families
// The system renders these tinted or monochrome regardless of the colors set here, so no
// custom color styling is applied — only structure and text.

struct InlineBossView: View {
    let boss: WidgetBossState?

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

struct CircularBossView: View {
    let boss: WidgetBossState?

    var body: some View {
        Gauge(value: max(0, min(100, 100 - (boss?.bestPercent ?? 100))), in: 0...100) {
            Text("\(boss?.bossOrdinal ?? 0)")
        } currentValueLabel: {
            Text(boss?.bestPercent != nil ? percentText(boss?.bestPercent) : "\(boss?.bossOrdinal ?? 0)")
                .font(.system(size: 13, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

struct RectangularBossView: View {
    let boss: WidgetBossState?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(boss?.bossName ?? "RWF Feed")
                .font(.headline)
                .lineLimit(1)
            if let guild = boss?.bestGuildName {
                Text("\(guild) · \(percentText(boss?.bestPercent))")
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text("No live pulls yet")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Shared

private struct BossIcon: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(WidgetTheme.accent.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview(as: .systemSmall) {
    RWFFeedWidget()
} timeline: {
    RWFTimelineEntry(date: .now, boss: .placeholder)
}

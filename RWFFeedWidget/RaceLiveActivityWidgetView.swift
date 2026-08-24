//
//  RaceLiveActivityWidgetView.swift
//  RWFFeedWidget
//
//  Dynamic Island + Lock Screen UI for the race Live Activity started from Settings — content
//  updates arrive via push from push-service (see worker.js), not this extension polling
//  anything itself.
//

import ActivityKit
import WidgetKit
import SwiftUI

private func liveActivityPercentText(_ percent: Double?) -> String {
    guard let percent else { return "—" }
    return String(format: "%.1f%%", percent)
}

struct RaceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceLiveActivityAttributes.self) { context in
            RaceLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(WidgetTheme.background)
                .activitySystemActionForegroundColor(WidgetTheme.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BOSS \(context.state.bossOrdinal)/\(context.state.totalBosses)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WidgetTheme.textSecondary)
                        Text(context.state.bossName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(liveActivityPercentText(context.state.bestPercent))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let guild = context.state.bestGuildName, let pulls = context.state.pullCount {
                        Text("\(guild) · \(pulls) pulls")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    } else {
                        Text("No live pulls yet")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                }
            } compactLeading: {
                Text("\(context.state.bossOrdinal)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent)
            } compactTrailing: {
                Text(liveActivityPercentText(context.state.bestPercent))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .monospacedDigit()
            } minimal: {
                Text(liveActivityPercentText(context.state.bestPercent))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent)
                    .monospacedDigit()
            }
        }
    }
}

private struct RaceLiveActivityLockScreenView: View {
    let state: RaceLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BOSS \(state.bossOrdinal)/\(state.totalBosses)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(state.bossName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                if let guild = state.bestGuildName, let pulls = state.pullCount {
                    Text("\(guild) · \(pulls) pulls")
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetTheme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("No live pulls yet")
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Text(liveActivityPercentText(state.bestPercent))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(WidgetTheme.accent)
                .monospacedDigit()
        }
        .padding(16)
    }
}

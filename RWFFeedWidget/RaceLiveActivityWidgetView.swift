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
import UIKit

private func liveActivityPercentText(_ percent: Double?) -> String {
    guard let percent else { return "—" }
    return String(format: "%.1f%%", percent)
}

struct RaceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceLiveActivityAttributes.self) { context in
            if context.state.isRaceComplete == true {
                RaceCompleteLockScreenView(state: context.state)
                    .activityBackgroundTint(WidgetTheme.background)
                    .activitySystemActionForegroundColor(WidgetTheme.textPrimary)
            } else {
                RaceLiveActivityLockScreenView(state: context.state)
                    .activityBackgroundTint(WidgetTheme.background)
                    .activitySystemActionForegroundColor(WidgetTheme.textPrimary)
            }
        } dynamicIsland: { context in
            if context.state.isRaceComplete == true {
                return DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(WidgetTheme.accent)
                            // The bottom region's full sentence already says the race is
                            // over, so this icon is redundant there — but it's the *only*
                            // content in compactLeading/minimal below, where it needs its
                            // own label instead.
                            .accessibilityHidden(true)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        Text("COMPLETE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        Text("\(context.state.winningGuildName ?? "The race") wins the Race to World First!")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WidgetTheme.textPrimary)
                            .lineLimit(2)
                    }
                } compactLeading: {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .accessibilityLabel("Race complete")
                } compactTrailing: {
                    EmptyView()
                } minimal: {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .accessibilityLabel("Race complete")
                }
            }
            return DynamicIsland {
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
                        Text("\(guild) · \(pulls) \(pulls == 1 ? "pull" : "pulls")")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    } else {
                        Text("No live pulls yet")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetTheme.textSecondary)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(context.state.bossOrdinal)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(WidgetTheme.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Boss \(context.state.bossOrdinal)")
            } compactTrailing: {
                if let percent = context.state.bestPercent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textPrimary)
                        .monospacedDigit()
                } else {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WidgetTheme.textSecondary)
                }
            } minimal: {
                if let percent = context.state.bestPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .monospacedDigit()
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .accessibilityLabel("Race in progress")
                }
            }
        }
    }
}

private struct RaceLiveActivityLockScreenView: View {
    let state: RaceLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let data = state.bossIconData, let uiImage = UIImage(data: data) {
                    // The source icon (36x36, kept small to fit inside APNs' push payload cap)
                    // is well below the Lock Screen's rendered size — nearest-neighbor scaling
                    // reads as a crisp pixel-art icon instead of the smeary blur bilinear
                    // upscaling produces at this ratio.
                    Image(uiImage: uiImage).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WidgetTheme.accent.opacity(0.25))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("BOSS \(state.bossOrdinal)/\(state.totalBosses)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(state.bossName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                if let guild = state.bestGuildName, let pulls = state.pullCount {
                    Text("\(guild) · \(pulls) \(pulls == 1 ? "pull" : "pulls")")
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

private struct RaceCompleteLockScreenView: View {
    let state: RaceLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 28))
                .foregroundStyle(WidgetTheme.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("RACE COMPLETE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text("\(state.winningGuildName ?? "Unknown") wins!")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                Text("Race to World First is over")
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

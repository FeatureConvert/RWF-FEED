//
//  WatchContentView.swift
//  RWFFeedWatch
//
//  A minimal standalone watch app — mainly here so complications have an app to belong to.
//  Shows the same "furthest boss being pulled" summary as the complications, full-size.
//

import SwiftUI
import WidgetKit

/// "1 pull" / "3 pulls" — this target's own copy of RWF FEED's Models.swift helper of the same
/// name (the watch app builds independently; see WatchBossData.swift's header comment).
private extension Int {
    var pullsLabel: String { self == 1 ? "\(self) pull" : "\(self) pulls" }
}

struct WatchContentView: View {
    @State private var boss: WatchBossState?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let boss {
                    Text("BOSS \(boss.bossOrdinal)/\(boss.totalBosses)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(boss.bossName)
                        .font(.system(size: 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("BEST LIVE PULL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    if let percent = boss.bestPercent {
                        Text(String(format: "%.1f%%", percent))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    if let guild = boss.bestGuildName, let pulls = boss.pullCount {
                        Text("\(guild) — \(pulls.pullsLabel)")
                            .font(.system(size: 13))
                    }

                    if !boss.top3.isEmpty {
                        Divider()

                        Text("TOP 3")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(boss.top3.enumerated()), id: \.offset) { index, standing in
                            HStack {
                                Text("\(index + 1). \(standing.guildName)")
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(standing.bossesDown)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Rank \(index + 1), \(standing.guildName), \(standing.bossesDown) bosses down")
                        }
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    Text("No live pulls yet")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            // Loops for as long as the view stays on screen — SwiftUI cancels a `.task` when
            // its view disappears, so this doesn't keep running once the watch face/app
            // switches away. Previously this only ever ran once on appear, so the on-wrist app
            // (and, via reloadAllTimelines, the complications) went stale until the next manual
            // pull-to-refresh or the next budgeted complication tick.
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
        .refreshable { await refresh() }
    }

    /// Bumped on every call and captured locally so a slow, earlier-started refresh (from the
    /// background loop above) can't overwrite a faster, later-started one (e.g. a manual
    /// pull-to-refresh that fires while the loop's own fetch is still in flight) with stale data.
    @State private var refreshGeneration = 0

    private func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let fetched = await RWFWatchData.fetchCurrentBoss()
        guard generation == refreshGeneration else { return }
        boss = fetched
        isLoading = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    WatchContentView()
}

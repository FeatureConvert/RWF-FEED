//
//  BossBreakdownViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class BossBreakdownViewModel: ObservableObject {
    @Published private(set) var summaries: [BossSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let service = RaiderIOService.shared
    private var pollTask: Task<Void, Never>?

    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        if summaries.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let trackerTask = service.fetchTracker()
            async let rankingsTask = service.fetchRaidRankings()
            // Best-effort: a Hall of Fame fetch failure just means no VOD links this cycle,
            // not a failed refresh — the boss list itself doesn't depend on it.
            async let hallOfFameTask = (try? await service.fetchHallOfFame()) ?? []
            let (tracker, rankings, hallOfFame) = try await (trackerTask, rankingsTask, hallOfFameTask)
            let vodBySlug = Dictionary(
                hallOfFame.compactMap { entry -> (String, URL)? in
                    guard let slug = entry.boss?.slug, let url = entry.bossKillVideo?.first?.twitchURL else { return nil }
                    return (slug, url)
                },
                uniquingKeysWith: { first, _ in first }
            )
            summaries = tracker.raid.bossSummaries(rankings: rankings).map { summary in
                guard let worldFirst = summary.worldFirst, let vodURL = vodBySlug[summary.boss.slug] else { return summary }
                var updated = worldFirst
                updated.vodURL = vodURL
                return BossSummary(boss: summary.boss, worldFirst: updated, bestPull: summary.bestPull)
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the boss list. Pull to try again."
        }
    }
}

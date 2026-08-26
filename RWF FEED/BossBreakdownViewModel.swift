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
    /// True once the world's leading guild (most confirmed kills — same invariant as everywhere
    /// else in this app) has defeated every boss in the raid. Drives the "Race Complete" recap
    /// banner; always world-scoped like the rest of this view model's Hall of Fame data.
    @Published private(set) var isRaceComplete = false
    /// World-scoped standings, ranked by confirmed kills — reused for the recap's final
    /// standings list rather than re-deriving a second ranking.
    @Published private(set) var finalStandings: [GuildStanding] = []
    /// Keyed by "\(guildId)-\(bossSlug)" — see PullTrend. Only ever has entries for pairs with
    /// an active undefeated pull old enough to say something meaningful about.
    @Published private(set) var pullTrends: [String: PullTrend] = [:]

    private let service = RaiderIOService.shared
    private let poller = Poller()

    func startPolling(interval: TimeInterval = 60) {
        poller.start(interval: interval) { [weak self] in await self?.refresh() }
    }

    func stopPolling() {
        poller.stop()
    }

    func refresh() async {
        if summaries.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let region = RegionFilter.shared.region.rawValue
            async let trackerTask = service.fetchTracker(region: region)
            async let rankingsTask = service.fetchRaidRankings(region: region)
            // Hall of Fame deliberately stays world-scoped regardless of the region filter — it
            // tracks genuine world-first kills, not "first in this region," so a VOD link
            // should only ever show up next to an actual world first. Best-effort: a fetch
            // failure just means no VOD links this cycle, not a failed refresh.
            async let hallOfFameTask = (try? await service.fetchHallOfFame()) ?? []
            async let velocityTask = service.fetchVelocitySnapshots()
            let (tracker, rankings, hallOfFame, velocitySnapshots) = try await (trackerTask, rankingsTask, hallOfFameTask, velocityTask)
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
            let worldStandings = tracker.standings(rankings: rankings)
            finalStandings = worldStandings
            isRaceComplete = (worldStandings.first?.bossesDown ?? 0) >= tracker.raid.encounters.count
                && !tracker.raid.encounters.isEmpty

            let snapshotByKey = Dictionary(
                velocitySnapshots.map { ("\($0.guildId)-\($0.bossSlug)", $0) },
                uniquingKeysWith: { first, _ in first }
            )
            pullTrends = summaries.reduce(into: [:]) { result, summary in
                guard let bestPull = summary.bestPull else { return }
                let key = "\(bestPull.guild.id)-\(summary.boss.slug)"
                guard let snapshot = snapshotByKey[key] else { return }
                result[key] = PullTrend.compute(currentPercent: bestPull.percent, snapshot: snapshot)
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the boss list. Pull to try again."
        }
    }
}

//
//  TrackerViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class TrackerViewModel: ObservableObject {
    @Published private(set) var standings: [GuildStanding] = []
    @Published private(set) var raid: RaidInfo?
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
        if standings.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let trackerTask = service.fetchTracker()
            // raid-race's guild.logo is stale/broken for some guilds even when raid-rankings
            // has a working one for the same guild (confirmed via device logs — a 403 from an
            // old per-raid asset path raid-race still references). Best-effort: a rankings
            // fetch failure just means no logo correction this cycle, not a failed refresh.
            async let rankingsTask = (try? await service.fetchRaidRankings()) ?? []
            let tracker = try await trackerTask
            let rankings = await rankingsTask
            raid = tracker.raid
            let logoByGuildId = Dictionary(rankings.map { ($0.guild.id, $0.guild.logo) }, uniquingKeysWith: { first, _ in first })
            let baseStandings = tracker.standings()
            let bossesDownByGuildId = Dictionary(uniqueKeysWithValues: baseStandings.map { ($0.guild.id, $0.bossesDown) })
            let currentPullByGuildId = tracker.raid.currentPulls(bossesDownByGuildId: bossesDownByGuildId, rankings: rankings)
            standings = baseStandings.map { standing in
                let guild = logoByGuildId[standing.guild.id].map { standing.guild.withLogo($0) } ?? standing.guild
                return GuildStanding(
                    guild: guild, bossesDown: standing.bossesDown,
                    lastKillAt: standing.lastKillAt, isLive: standing.isLive,
                    currentPull: currentPullByGuildId[standing.guild.id]
                )
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the tracker. Pull to try again."
        }
    }
}

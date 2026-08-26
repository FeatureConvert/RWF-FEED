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
    /// The full raid-rankings entry per guild — what GuildDetailView renders (boss-by-boss
    /// kill times, pull counts) beyond the condensed GuildStanding row.
    @Published private(set) var rankingByGuildId: [Int: RaidRankingEntry] = [:]
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
            let region = RegionFilter.shared.region.rawValue
            // Both fetches are load-bearing now: raid-rankings IS the leaderboard (served
            // rank, defeat counts, kill times, live pulls), while raid-race supplies the
            // raid's encounter metadata and the live-streams list.
            async let trackerTask = service.fetchTracker(region: region)
            async let rankingsTask = service.fetchRaidRankings(region: region)
            let (tracker, rankings) = try await (trackerTask, rankingsTask)
            raid = tracker.raid
            standings = tracker.standings(rankings: rankings)
            rankingByGuildId = Dictionary(rankings.map { ($0.guild.id, $0) }, uniquingKeysWith: { first, _ in first })
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the tracker. Pull to try again."
        }
    }
}

//
//  KillFeedViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class KillFeedViewModel: ObservableObject {
    @Published private(set) var groups: [BossKillGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let service = RaiderIOService.shared
    private let poller = Poller()

    func startPolling(interval: TimeInterval = 30) {
        poller.start(interval: interval) { [weak self] in await self?.refresh() }
    }

    func stopPolling() {
        poller.stop()
    }

    func refresh() async {
        if groups.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            // raid-rankings is the actual data source now (see
            // WorldFirstTracker.killFeedGroups(rankings:)), not just a best-effort logo
            // correction — a failure here is a real failed refresh, not silently empty kills.
            let region = RegionFilter.shared.region.rawValue
            async let trackerTask = service.fetchTracker(region: region)
            async let rankingsTask = service.fetchRaidRankings(region: region)
            let tracker = try await trackerTask
            let rankings = try await rankingsTask
            groups = tracker.killFeedGroups(rankings: rankings, maxRank: 3)
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the kill feed. Pull to try again."
        }
    }
}

//
//  KillFeedViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class KillFeedViewModel: ObservableObject {
    @Published private(set) var events: [KillFeedEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let service = RaiderIOService.shared
    private var pollTask: Task<Void, Never>?

    func startPolling(interval: TimeInterval = 30) {
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
        if events.isEmpty { isLoading = true }
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
            let logoByGuildId = Dictionary(rankings.map { ($0.guild.id, $0.guild.logo) }, uniquingKeysWith: { first, _ in first })
            events = tracker.killFeedEvents().map { event in
                guard let logo = logoByGuildId[event.guild.id] else { return event }
                return KillFeedEvent(
                    guild: event.guild.withLogo(logo), boss: event.boss, rank: event.rank,
                    defeatedAt: event.defeatedAt
                )
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the kill feed. Pull to try again."
        }
    }
}

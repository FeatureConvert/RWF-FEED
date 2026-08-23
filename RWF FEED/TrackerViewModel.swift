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
            let tracker = try await service.fetchTracker()
            raid = tracker.raid
            standings = tracker.standings()
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the tracker. Pull to try again."
        }
    }
}

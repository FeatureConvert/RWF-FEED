//
//  HeartbreakViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class HeartbreakViewModel: ObservableObject {
    @Published private(set) var closeCalls: [CloseCall] = []
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
        if closeCalls.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let trackerTask = service.fetchTracker()
            async let rankingsTask = service.fetchRaidRankings()
            let (tracker, rankings) = try await (trackerTask, rankingsTask)
            closeCalls = tracker.raid.closeCalls(rankings: rankings)
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load close calls. Pull to try again."
        }
    }
}

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
    /// Keyed by "\(guildId)-\(bossSlug)" — see PullTrend.
    @Published private(set) var pullTrends: [String: PullTrend] = [:]

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
            let region = RegionFilter.shared.region.rawValue
            async let trackerTask = service.fetchTracker(region: region)
            async let rankingsTask = service.fetchRaidRankings(region: region)
            async let velocityTask = service.fetchVelocitySnapshots()
            let (tracker, rankings, velocitySnapshots) = try await (trackerTask, rankingsTask, velocityTask)
            // Was hardcoded to the service's own 10% default, independent of the Settings
            // slider — which only ever controlled the push notification trigger, not what this
            // tab itself displayed, so tightening/loosening the slider visibly did nothing here.
            closeCalls = tracker.raid.closeCalls(rankings: rankings, maxPercent: NotificationPreferences.shared.heartbreakThresholdPercent)

            let snapshotByKey = Dictionary(
                velocitySnapshots.map { ("\($0.guildId)-\($0.bossSlug)", $0) },
                uniquingKeysWith: { first, _ in first }
            )
            pullTrends = closeCalls.reduce(into: [:]) { result, call in
                let key = "\(call.guild.id)-\(call.boss.slug)"
                guard let snapshot = snapshotByKey[key] else { return }
                result[key] = PullTrend.compute(currentPercent: call.percent, snapshot: snapshot)
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load close calls. Pull to try again."
        }
    }
}

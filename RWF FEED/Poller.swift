//
//  Poller.swift
//  RWF FEED
//
//  The startPolling(interval:)/stopPolling()/pollTask loop every ViewModel in this app used to
//  hand-roll independently (FeedViewModel, TrackerViewModel, KillFeedViewModel,
//  BossBreakdownViewModel, HeartbreakViewModel, NewsViewModel — six near-identical copies).
//  This factors out just the loop mechanism itself, not each screen's loading/error-state
//  semantics (those genuinely differ per screen — e.g. what counts as "first load" — so they
//  stay owned by each ViewModel rather than being forced into a shared shape here).
//

import Foundation

@MainActor
final class Poller {
    private var task: Task<Void, Never>?

    /// Runs `action` immediately, then again every `interval` seconds, until `stop()` is called
    /// or this `Poller` is deallocated. Calling `start` again cancels any loop already running.
    func start(interval: TimeInterval, action: @escaping () async -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                await action()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

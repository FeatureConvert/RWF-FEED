//
//  FeedViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var posts: [FeedPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = RaiderIOService.shared
    private var pollTask: Task<Void, Never>?

    /// Highest post id we've already shown/notified about, persisted so a relaunch doesn't
    /// treat the whole existing feed as "new" and fire a notification storm.
    private static let lastSeenKey = "FeedViewModel.lastSeenPostID"

    func startPolling(interval: TimeInterval = 30) {
        NotificationManager.shared.requestAuthorizationIfNeeded()
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
        if posts.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchFeed()
            notifyAboutNewPosts(in: fetched)
            posts = fetched
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the feed. Pull to try again."
        }
    }

    private func notifyAboutNewPosts(in fetched: [FeedPost]) {
        guard let latestId = fetched.map(\.id).max() else { return }
        let defaults = UserDefaults.standard
        defer { defaults.set(latestId, forKey: Self.lastSeenKey) }

        // First-ever launch: just record the baseline, don't notify about the whole backlog.
        guard let lastSeenId = defaults.object(forKey: Self.lastSeenKey) as? Int else { return }

        let newPosts = fetched
            .filter { $0.id > lastSeenId }
            .sorted { $0.publishedAt < $1.publishedAt }
        for post in newPosts {
            NotificationManager.shared.notifyNewPost(post)
        }
    }
}

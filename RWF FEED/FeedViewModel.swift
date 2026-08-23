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
            posts = try await service.fetchFeed()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the feed. Pull to try again."
        }
    }
}

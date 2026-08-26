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
        if posts.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            posts = try await service.fetchFeed()
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the feed. Pull to try again."
        }
    }
}

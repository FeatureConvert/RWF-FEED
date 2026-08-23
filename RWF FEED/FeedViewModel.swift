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
    /// Each post's HTML, parsed once and cached — FeedPostRow used to call
    /// PostContent.parseBlocks(from:) directly in its `body`, re-parsing (main-thread,
    /// WebKit-backed) on every row re-render instead of once per post.
    @Published private(set) var blocksByPostID: [Int: [PostContentBlock]] = [:]

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
            let fetched = try await service.fetchFeed()
            posts = fetched
            errorMessage = nil
            await parseNewBlocks(for: fetched)
        } catch {
            errorMessage = "Couldn't load the feed. Pull to try again."
        }
    }

    /// Parses only posts we haven't already cached, off the main actor and in parallel —
    /// each poll only ever adds a couple of new posts, so this is normally near-instant.
    private func parseNewBlocks(for posts: [FeedPost]) async {
        let newPosts = posts.filter { blocksByPostID[$0.id] == nil }
        guard !newPosts.isEmpty else { return }

        let parsed = await withTaskGroup(of: (Int, [PostContentBlock]).self) { group in
            for post in newPosts {
                group.addTask {
                    (post.id, PostContent.parseBlocks(from: post.content ?? ""))
                }
            }
            var results: [Int: [PostContentBlock]] = [:]
            for await (id, blocks) in group {
                results[id] = blocks
            }
            return results
        }

        for (id, blocks) in parsed {
            blocksByPostID[id] = blocks
        }
    }
}

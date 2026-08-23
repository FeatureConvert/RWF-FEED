//
//  NewsViewModel.swift
//  RWF FEED
//

import Foundation
import Combine

@MainActor
final class NewsViewModel: ObservableObject {
    @Published private(set) var articles: [WowheadArticle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private static let feedURL = URL(string: "https://www.wowhead.com/news/rss/retail")!

    private var pollTask: Task<Void, Never>?

    func startPolling(interval: TimeInterval = 300) {
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
        if articles.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.feedURL)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            articles = WowheadFeedParser.parse(data)
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load WoW news. Pull to try again."
        }
    }
}

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

    private let poller = Poller()

    func startPolling(interval: TimeInterval = 300) {
        poller.start(interval: interval) { [weak self] in await self?.refresh() }
    }

    func stopPolling() {
        poller.stop()
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

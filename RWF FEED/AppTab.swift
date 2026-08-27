//
//  AppTab.swift
//  RWF FEED
//

import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case feed, tracker, bosses, heartbreak, news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .tracker: return "Tracker"
        case .bosses: return "Bosses"
        case .heartbreak: return "Heartbreak"
        case .news: return "News"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "bolt.fill"
        case .tracker: return "list.number"
        case .bosses: return "chart.bar.fill"
        case .heartbreak: return "heart.slash.fill"
        case .news: return "newspaper.fill"
        }
    }
}

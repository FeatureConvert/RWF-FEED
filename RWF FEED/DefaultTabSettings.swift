//
//  DefaultTabSettings.swift
//  RWF FEED
//
//  Which tab the app opens into at launch, set from Settings. Defaults to Feed.
//

import Foundation
import Combine

@MainActor
final class DefaultTabSettings: ObservableObject {
    static let shared = DefaultTabSettings()

    private static let key = "DefaultTabSettings.defaultTab"

    @Published var defaultTab: AppTab {
        didSet {
            UserDefaults.standard.set(defaultTab.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppTab.feed.rawValue
        defaultTab = AppTab(rawValue: raw) ?? .feed
    }
}

//
//  ContentView.swift
//  RWF FEED
//
//  Created by Robert Houston on 8/22/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab
    /// Each tab's view (and its @StateObject view model / polling task) is created the first
    /// time it's selected, then kept alive and just visually swapped after that — matching how
    /// a real TabView behaves, rather than eagerly starting all 6 tabs' polling at launch.
    @State private var visitedTabs: Set<AppTab>

    init() {
        let startingTab = DefaultTabSettings.shared.defaultTab
        _selectedTab = State(initialValue: startingTab)
        _visitedTabs = State(initialValue: [startingTab])
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if visitedTabs.contains(.feed) { tab(.feed) { FeedView(isActive: selectedTab == .feed) } }
                if visitedTabs.contains(.tracker) { tab(.tracker) { TrackerView(isActive: selectedTab == .tracker) } }
                if visitedTabs.contains(.kills) { tab(.kills) { KillFeedView(isActive: selectedTab == .kills) } }
                if visitedTabs.contains(.bosses) { tab(.bosses) { BossBreakdownView(isActive: selectedTab == .bosses) } }
                if visitedTabs.contains(.heartbreak) { tab(.heartbreak) { HeartbreakView(isActive: selectedTab == .heartbreak) } }
                if visitedTabs.contains(.news) { tab(.news) { NewsView(isActive: selectedTab == .news) } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selection: $selectedTab)
        }
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
        .background(Theme.background)
        .onChange(of: selectedTab) { _, newValue in
            visitedTabs.insert(newValue)
        }
    }

    @ViewBuilder
    private func tab<Content: View>(_ value: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == value ? 1 : 0)
            .allowsHitTesting(selectedTab == value)
            .accessibilityHidden(selectedTab != value)
    }
}

#Preview {
    ContentView()
}

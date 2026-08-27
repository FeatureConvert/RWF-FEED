//
//  ContentView.swift
//  RWF FEED
//
//  Created by Robert Houston on 8/22/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab
    @ObservedObject private var notificationRouter = NotificationRouter.shared

    init() {
        _selectedTab = State(initialValue: DefaultTabSettings.shared.defaultTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent { FeedView(isActive: selectedTab == .feed) }
                .tabItem { Label(AppTab.feed.title, systemImage: AppTab.feed.icon) }
                .tag(AppTab.feed)

            tabContent { TrackerView(isActive: selectedTab == .tracker) }
                .tabItem { Label(AppTab.tracker.title, systemImage: AppTab.tracker.icon) }
                .tag(AppTab.tracker)

            tabContent { BossBreakdownView(isActive: selectedTab == .bosses) }
                .tabItem { Label(AppTab.bosses.title, systemImage: AppTab.bosses.icon) }
                .tag(AppTab.bosses)

            tabContent { HeartbreakView(isActive: selectedTab == .heartbreak) }
                .tabItem { Label(AppTab.heartbreak.title, systemImage: AppTab.heartbreak.icon) }
                .tag(AppTab.heartbreak)

            tabContent { NewsView(isActive: selectedTab == .news) }
                .tabItem { Label(AppTab.news.title, systemImage: AppTab.news.icon) }
                .tag(AppTab.news)
        }
        .tint(Theme.accent)
        .onChange(of: notificationRouter.pendingTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            notificationRouter.pendingTab = nil
        }
    }

    /// Caps content width on wide screens; each tab paints its own Theme.background,
    /// so the gutters outside the cap need painting here to match.
    @ViewBuilder
    private func tabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
    }
}

#Preview {
    ContentView()
}

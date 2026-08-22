//
//  ContentView.swift
//  RWF FEED
//
//  Created by Robert Houston on 8/22/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "bolt.fill") }

            TrackerView()
                .tabItem { Label("Tracker", systemImage: "list.number") }

            KillFeedView()
                .tabItem { Label("Kills", systemImage: "checkmark.seal.fill") }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    ContentView()
}

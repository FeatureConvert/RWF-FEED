//
//  RWF_FEEDApp.swift
//  RWF FEED
//
//  Created by Robert Houston on 8/22/26.
//

import SwiftUI

@main
struct RWF_FEEDApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .opensLinksInApp()
                .onAppear {
                    // The window doesn't exist yet at AppearanceSettings.init() time, so the
                    // persisted mode needs to be (re-)applied once a window actually exists.
                    AppearanceSettings.shared.applyToWindows()
                    // Was previously only triggered from FeedViewModel.startPolling(), which
                    // meant a user whose Default Tab wasn't Feed could go a whole session
                    // without ever registering for push (or re-registering a rotated APNs
                    // token) — belongs at the app level, not inside one tab's view model.
                    NotificationManager.shared.requestAuthorizationIfNeeded()
                }
        }
    }
}

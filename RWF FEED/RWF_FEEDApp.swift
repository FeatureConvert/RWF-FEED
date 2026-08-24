//
//  RWF_FEEDApp.swift
//  RWF FEED
//
//  Created by Robert Houston on 8/22/26.
//

import SwiftUI
import UserNotifications

@main
struct RWF_FEEDApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
        // Primary badge-clear trigger — scenePhase is the SwiftUI-native signal for this and
        // fires reliably regardless of how the scene became active (cold launch, foreground,
        // notification tap). AppDelegate.applicationDidBecomeActive does the same thing as a
        // second, UIKit-side path; redundant but harmless, since setBadgeCount(0) twice is a
        // no-op the second time.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UNUserNotificationCenter.current().setBadgeCount(0)
            }
        }
    }
}

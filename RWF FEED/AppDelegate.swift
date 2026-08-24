//
//  AppDelegate.swift
//  RWF FEED
//
//  Makes new-post notification banners show up even while the app is open in the
//  foreground (UNUserNotificationCenter suppresses them by default otherwise), and wires
//  up remote push: new-post notifications are sent by the push-service Worker so they
//  arrive even while the app is fully closed, not just while polling is running.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Every AsyncImage in the app (boss icons, News thumbnails — guild logos have their
        // own in-memory cache, see GuildAvatar) shares URLCache.shared under the hood with no
        // retry on a failed load. The system default capacity is easily thrashed once dozens
        // of unique images are being polled across 5+ tabs every 30-60s, and a cache-
        // eviction-driven miss just permanently shows the fallback for that render — a
        // bigger, dedicated cache makes that far less likely without touching any view code.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistration.register(deviceToken: deviceToken)
    }

    // The push Worker always requests badge: 1 (see push-service/src/worker.js — there's no
    // real per-device unread count to send), so it never clears itself. Clearing here on every
    // foreground means it reads as "there's something new" rather than getting stuck on
    // forever after the user's already seen it.
    func applicationDidBecomeActive(_ application: UIApplication) {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("AppDelegate: failed to register for remote notifications: %@", String(describing: error))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    // Tapping a notification only opens the app to whatever Default Tab is set, not wherever
    // that notification is actually about — a "Major Heartbreaker" push should land on
    // Heartbreak, not wherever the user happened to leave the app. The push payload carries a
    // top-level "tab" string (see push-service/src/worker.js's sendPush) matching AppTab's raw
    // values; NotificationRouter bridges it from this UIKit callback into SwiftUI.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // UNUserNotificationCenterDelegate callbacks aren't guaranteed to land on the main
        // actor, but NotificationRouter is — hop over explicitly rather than assuming.
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if let tabRaw = userInfo["tab"] as? String, let tab = AppTab(rawValue: tabRaw) {
                NotificationRouter.shared.pendingTab = tab
            }
        }
        completionHandler()
    }
}

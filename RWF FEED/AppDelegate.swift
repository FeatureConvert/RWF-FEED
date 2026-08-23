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
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        MobileAds.shared.start(completionHandler: nil)
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
}

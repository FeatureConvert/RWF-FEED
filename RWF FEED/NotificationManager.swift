//
//  NotificationManager.swift
//  RWF FEED
//
//  New-post notifications are delivered by the push-service Worker (see
//  push-service/README.md), which polls raider.io on a 1-minute cron and pushes via APNs —
//  that's what lets a notification arrive while the app is fully closed. This type only
//  handles the client side: asking for permission and registering for a device token.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized else { return }
            // Safe to call every launch — the system no-ops if the token hasn't changed,
            // and re-registers if it has.
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}

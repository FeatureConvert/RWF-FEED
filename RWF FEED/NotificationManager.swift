//
//  NotificationManager.swift
//  RWF FEED
//
//  Local notifications for new feed posts. There's no push server behind raider.io's
//  coverage feed, so this fires from the app's own polling loop — it only delivers while
//  the app is running (foreground, or briefly after backgrounding), not while fully closed.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func notifyNewPost(_ post: FeedPost) {
        let content = UNMutableNotificationContent()
        content.title = post.author ?? "Global Coverage"
        let body = post.contentPreview ?? post.content?.strippingHTMLTags() ?? "New update"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: "post-\(post.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("NotificationManager: failed to schedule notification for post %d: %@", post.id, String(describing: error))
            }
        }
    }
}

//
//  RaceLiveActivityController.swift
//  RWF FEED
//
//  Starts/stops the race Live Activity and keeps push-service's live-activity-token registry
//  in sync with ActivityKit's own push token — the Worker sends content updates to that token
//  as the leader's frontier boss changes (see push-service/src/worker.js).
//

import Foundation
import ActivityKit
import Combine

@MainActor
final class RaceLiveActivityController: ObservableObject {
    static let shared = RaceLiveActivityController()

    @Published private(set) var isActive: Bool

    private var tokenTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var lastKnownTokenHex: String?

    private static let registerURL = URL(string: "https://rwf-feed-push.rwf-feed.workers.dev/live-activity/register")!
    private static let unregisterURL = URL(string: "https://rwf-feed-push.rwf-feed.workers.dev/live-activity/unregister")!

    private init() {
        // Reconnect to an activity still running from a previous launch (e.g. app was killed
        // and reopened) so the Settings toggle reflects reality instead of always starting nil.
        if let existing = Activity<RaceLiveActivityAttributes>.activities.first {
            isActive = true
            observePushToken(for: existing)
            observeActivityState(for: existing)
        } else {
            isActive = false
        }
    }

    func start(content: RaceLiveActivityAttributes.ContentState) {
        guard Activity<RaceLiveActivityAttributes>.activities.isEmpty else { return }
        let attributes = RaceLiveActivityAttributes(raidName: "The Venomous Abyss")
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: content, staleDate: nil),
                pushType: .token
            )
            isActive = true
            observePushToken(for: activity)
            observeActivityState(for: activity)
        } catch {
            NSLog("RaceLiveActivityController: failed to start Live Activity: %@", String(describing: error))
        }
    }

    func stop() {
        tokenTask?.cancel()
        tokenTask = nil
        stateTask?.cancel()
        stateTask = nil
        isActive = false
        Task {
            for activity in Activity<RaceLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let tokenHex = lastKnownTokenHex {
            Task { await Self.send(to: Self.unregisterURL, tokenHex: tokenHex) }
        }
    }

    private func observePushToken(for activity: Activity<RaceLiveActivityAttributes>) {
        tokenTask?.cancel()
        tokenTask = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
                self?.lastKnownTokenHex = tokenHex
                await Self.send(to: Self.registerURL, tokenHex: tokenHex)
            }
        }
    }

    /// Keeps `isActive` (and Settings' Start/Stop button) honest when the activity ends for a
    /// reason we didn't initiate ourselves — swiped away from the Lock Screen, the system's
    /// 8-hour timeout, etc. — not just when our own `stop()` is called.
    private func observeActivityState(for activity: Activity<RaceLiveActivityAttributes>) {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard state == .dismissed || state == .ended else { continue }
                guard let self else { return }
                self.isActive = false
                self.tokenTask?.cancel()
                self.tokenTask = nil
                if let tokenHex = self.lastKnownTokenHex {
                    await Self.send(to: Self.unregisterURL, tokenHex: tokenHex)
                }
                return
            }
        }
    }

    private static func send(to url: URL, tokenHex: String) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["pushToken": tokenHex])
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            NSLog("RaceLiveActivityController: request to %@ failed: %@", url.absoluteString, String(describing: error))
        }
    }
}

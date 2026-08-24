//
//  NotificationRouter.swift
//  RWF FEED
//
//  Bridges a tapped push notification (handled by AppDelegate, a UIKit type) to ContentView's
//  SwiftUI tab selection. AppDelegate sets pendingTab when a notification is tapped; ContentView
//  observes it and switches tabs, then clears it so the same tap doesn't re-fire on a later
//  unrelated view update.
//

import Foundation
import Combine

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published var pendingTab: AppTab?

    private init() {}
}

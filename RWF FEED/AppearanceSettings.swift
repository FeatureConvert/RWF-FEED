//
//  AppearanceSettings.swift
//  RWF FEED
//
//  Persists the user's light/dark/system appearance choice and applies it by overriding
//  every window's UIKit trait collection directly (UIWindow.overrideUserInterfaceStyle)
//  rather than relying on SwiftUI's .preferredColorScheme — that modifier doesn't reliably
//  propagate into a .sheet's own presentation hierarchy when it's set on an ancestor further
//  up the view tree, which left the Settings sheet itself not respecting the chosen mode.
//  Theme.swift's colors are all already adaptive (Color.adaptive(darkHex:lightHex:)), so
//  overriding the window trait is the only wiring needed — every screen picks it up.
//

import SwiftUI
import UIKit
import Combine

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()

    private static let key = "AppearanceSettings.mode"

    @Published var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
            applyToWindows()
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppearanceMode.system.rawValue
        mode = AppearanceMode(rawValue: raw) ?? .system
    }

    /// Called once at launch (the app's scenes/windows don't exist yet at `init()` time) and
    /// again from `mode`'s didSet on every change.
    func applyToWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = mode.uiStyle
            }
        }
    }
}

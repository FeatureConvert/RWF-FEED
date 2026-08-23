//
//  AppearanceSettings.swift
//  RWF FEED
//
//  Persists the user's light/dark/system appearance choice. Theme.swift's colors are all
//  already adaptive (Color.adaptive(darkHex:lightHex:)), so applying .preferredColorScheme
//  at the root is the only wiring needed — every screen picks up the change automatically.
//

import SwiftUI
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

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
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
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppearanceMode.system.rawValue
        mode = AppearanceMode(rawValue: raw) ?? .system
    }
}

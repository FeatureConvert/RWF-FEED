//
//  RegionFilter.swift
//  RWF FEED
//
//  Which region's standings Tracker/Kills/Bosses/Heartbreak show — raider.io's own raid-race
//  and raid-rankings endpoints accept a region query param directly (confirmed live: us/eu/kr/
//  cn all return real, distinct data; tw currently empty for this raid tier), so this is just a
//  passthrough filter, not something computed client-side. World (every region combined) is the
//  default and matches the app's original, only behavior.
//

import Foundation
import Combine

enum RaceRegion: String, CaseIterable, Identifiable {
    case world, us, eu, kr, tw, cn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .world: return "World"
        case .us: return "US"
        case .eu: return "EU"
        case .kr: return "KR"
        case .tw: return "TW"
        case .cn: return "CN"
        }
    }
}

@MainActor
final class RegionFilter: ObservableObject {
    static let shared = RegionFilter()

    private static let key = "RegionFilter.region"

    @Published var region: RaceRegion {
        didSet { UserDefaults.standard.set(region.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? RaceRegion.world.rawValue
        region = RaceRegion(rawValue: raw) ?? .world
    }
}

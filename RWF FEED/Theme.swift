//
//  Theme.swift
//  RWF FEED
//
//  Design tokens from the "RWF FEED UI Spec" Claude Design project — a Nocturne-based
//  dark/purple system with a single semantic red for the LIVE badge. Values are hand-ported
//  from the spec's hex/opacity table rather than generated, so this file is the source of
//  truth for the app's look going forward.
//
//  Typography note: the spec calls for bundling Inter (weights 400/500/600/700) via
//  Font.custom, replacing SF entirely. That requires shipping font files and registering
//  them in Info.plist (UIAppFonts), which this project's auto-generated Info.plist doesn't
//  support without switching to an explicit plist file — a real build-system change. Until
//  that's worth doing, Theme.font(_:) below reproduces the spec's weight/size/tracking table
//  on the system font, which is visually very close to Inter at these sizes.
//

import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// A color that resolves to a different hex/opacity pair per light/dark appearance.
    static func adaptive(darkHex: String, darkOpacity: Double = 1, lightHex: String, lightOpacity: Double = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: darkHex, opacity: darkOpacity))
                : UIColor(Color(hex: lightHex, opacity: lightOpacity))
        })
    }
}

enum Theme {
    // MARK: Palette

    static let background = Color.adaptive(darkHex: "#161826", lightHex: "#E4E7F5")
    static let cardSurface = Color.adaptive(darkHex: "#232532", lightHex: "#F3F5FE")
    static let textPrimary = Color.adaptive(darkHex: "#E9E9ED", lightHex: "#292B31")
    static let textSecondary = Color.adaptive(darkHex: "#E9E9ED", darkOpacity: 0.6, lightHex: "#292B31", lightOpacity: 0.6)

    /// Icons/chrome — one hue in both modes.
    static let accent = Color(hex: "#9184D9")
    /// Links/body-size accent text — light mode drops to a darker ramp step for contrast.
    static let accentText = Color.adaptive(darkHex: "#9184D9", lightHex: "#5D5294")

    static let tagFill = Color.adaptive(darkHex: "#423A6A", lightHex: "#F5F4FF")
    static let tagText = Color.adaptive(darkHex: "#F5F4FF", lightHex: "#5D5294")

    static let star = Color.adaptive(darkHex: "#D2CEFD", lightHex: "#796CBF")

    static let divider = Color.adaptive(darkHex: "#E9E9ED", darkOpacity: 0.16, lightHex: "#292B31", lightOpacity: 0.12)

    /// The one fixed, non-ramp color in the system — broadcast convention overrides brand consistency here.
    static let live = Color(hex: "#E5484D")

    // MARK: Spacing & shape

    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let cardGap: CGFloat = 8
    static let cardRowGap: CGFloat = 8
    static let guildLogoDiameter: CGFloat = 36
    static let trackerRowVPadding: CGFloat = 10
    static let trackerRowHPadding: CGFloat = 16
    static let trackerRowColumnGap: CGFloat = 12
    /// Width of the leading rank/ordinal number column shared by GuildStandingRow and
    /// BossSummaryRow — also what nested/indented rows (e.g. BossSummaryRow's disclosed
    /// KillFeedRow) offset past to align under the row's title text instead of its number.
    static let rankColumnWidth: CGFloat = 22
    static let tagCornerRadius: CGFloat = 6
    static let tagHPadding: CGFloat = 8
    static let tagVPadding: CGFloat = 3
    static let screenEdgeMargin: CGFloat = 16
    /// Caps the whole app's width on iPad/landscape-iPhone — this is a single-column,
    /// phone-shaped layout throughout (List/ScrollView content, a 6-item bottom tab bar), and
    /// letting it stretch to a full iPad's width blows out card widths and spaces the tab bar
    /// icons apart absurdly rather than looking like a real iPad layout. Matches the cap
    /// FeedView already used for its own landscape centering before this existed app-wide.
    static let maxContentWidth: CGFloat = 700

    // MARK: Typography

    /// Reproduces the spec's Inter weight/size/tracking table on the system font, scaled by the
    /// user's Dynamic Type setting via UIFontMetrics — `Font.system(size:weight:)` alone never
    /// scales regardless of Dynamic Type, by design (only text-style-based fonts do). Scaled
    /// relative to `.body` uniformly rather than a per-token text style: simpler than picking a
    /// "correct" style per size, and every token in this design system moves together as text
    /// size changes instead of drifting relative to each other.
    ///
    /// A `var`, not a `let`, at every call site below (`static var rankNumber: Font { ... }`,
    /// not `static let rankNumber = ...`) — a `let` would cache the scaled value from whenever
    /// it was first accessed and never update again for the rest of the process, even though
    /// the system's text size can change live (Control Center) while the app stays foregrounded.
    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        let uiFont = UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
        return Font(UIFontMetrics.default.scaledFont(for: uiFont))
    }

    static var authorName: Font { font(size: 15, weight: .semibold) }
    static var postBody: Font { font(size: 15, weight: .regular) }
    static var timestamp: Font { font(size: 12, weight: .regular) }
    static var tagLabel: Font { font(size: 11, weight: .semibold) }
    static let tagLabelTracking: CGFloat = 11 * 0.02
    static var rankNumber: Font { font(size: 17, weight: .semibold) }
    static var bossProgress: Font { font(size: 15, weight: .semibold) }
    static var elapsedTimer: Font { font(size: 11, weight: .regular) }
    static var liveBadgeLabel: Font { font(size: 10, weight: .bold) }
    static let liveBadgeTracking: CGFloat = 10 * 0.04
    static var screenTitle: Font { font(size: 20, weight: .medium) }
}

extension Font {
    /// A Dynamic-Type-scaled drop-in for `.system(size:weight:)`, which never scales on its
    /// own. Same UIFontMetrics mechanism as `Theme.font(size:weight:)` — exposed here too since
    /// most of this app's fonts are built ad hoc inline (`.font(.system(size: 12))`) rather
    /// than through a named Theme token, and all of them should scale the same way.
    static func rwf(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Theme.font(size: size, weight: weight)
    }
}

extension Font.Weight {
    /// SwiftUI's `Font.Weight` and UIKit's `UIFont.Weight` are separate types with no built-in
    /// bridge — needed here because UIFontMetrics (the only API that scales a custom point size
    /// with Dynamic Type) is UIKit, not SwiftUI.
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .black: return .black
        case .heavy: return .heavy
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .regular: return .regular
        case .light: return .light
        case .thin: return .thin
        case .ultraLight: return .ultraLight
        default: return .regular
        }
    }
}

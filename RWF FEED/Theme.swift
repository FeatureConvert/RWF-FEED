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
    static let tagCornerRadius: CGFloat = 6
    static let tagHPadding: CGFloat = 8
    static let tagVPadding: CGFloat = 3
    static let screenEdgeMargin: CGFloat = 16

    // MARK: Typography

    /// Reproduces the spec's Inter weight/size/tracking table on the system font.
    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight)
    }

    static let authorName = font(size: 15, weight: .semibold)
    static let postBody = font(size: 15, weight: .regular)
    static let timestamp = font(size: 12, weight: .regular)
    static let tagLabel = font(size: 11, weight: .semibold)
    static let tagLabelTracking: CGFloat = 11 * 0.02
    static let rankNumber = font(size: 17, weight: .semibold)
    static let bossProgress = font(size: 15, weight: .semibold)
    static let elapsedTimer = font(size: 11, weight: .regular)
    static let liveBadgeLabel = font(size: 10, weight: .bold)
    static let liveBadgeTracking: CGFloat = 10 * 0.04
    static let screenTitle = font(size: 20, weight: .medium)
}

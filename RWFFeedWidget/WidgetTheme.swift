//
//  WidgetTheme.swift
//  RWFFeedWidget
//
//  A minimal, duplicated subset of the main app's Theme.swift palette — just enough for the
//  Home Screen widget families. Lock Screen/StandBy accessory families ignore custom colors
//  entirely (the system renders them tinted/monochrome), so this only matters for
//  systemSmall/Medium/Large/ExtraLarge.
//

import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

enum WidgetTheme {
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(Color(hex: "#161826")) : UIColor(Color(hex: "#E4E7F5"))
    })
    static let textPrimary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(Color(hex: "#E9E9ED")) : UIColor(Color(hex: "#292B31"))
    })
    static let textSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(Color(hex: "#E9E9ED")).withAlphaComponent(0.6) : UIColor(Color(hex: "#292B31")).withAlphaComponent(0.6)
    })
    static let accent = Color(hex: "#9184D9")
}

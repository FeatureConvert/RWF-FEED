//
//  SharedTrackerComponents.swift
//  RWF FEED
//
//  Small pieces shared between TrackerView (standings) and KillFeedView (kill log) —
//  both render guilds and need the same avatar/badge/divider treatment.
//

import SwiftUI

struct GuildAvatar: View {
    let guild: RaceGuild

    private static let palette: [(background: Color, foreground: Color)] = [
        (Color(hex: "#5D5294"), .white),
        (Color(hex: "#796CBF"), .white),
        (Color.adaptive(darkHex: "#75798C", lightHex: "#9397AB"), .white),
        (Color(hex: "#B5ABFC"), Color(hex: "#292B31")),
    ]

    private var initials: String {
        let words = guild.displayName.split(separator: " ")
        if words.count >= 2 {
            return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(guild.displayName.prefix(2)).uppercased()
    }

    private var colors: (background: Color, foreground: Color) {
        Self.palette[abs(guild.id) % Self.palette.count]
    }

    var body: some View {
        AsyncImage(url: URL(string: guild.logo)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Circle().fill(colors.background)
                    Text(initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.foreground)
                }
            }
        }
        .frame(width: Theme.guildLogoDiameter, height: Theme.guildLogoDiameter)
        .clipShape(Circle())
    }
}

struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(Theme.liveBadgeLabel)
            .tracking(Theme.liveBadgeTracking)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.live, in: Capsule())
    }
}

/// A fixed light-lavender pill, same in both appearance modes — like `Theme.live`, this one
/// doesn't ramp with light/dark since it's a badge convention rather than themed chrome.
struct WorldFirstBadge: View {
    var body: some View {
        Text("WORLD FIRST")
            .font(Theme.liveBadgeLabel)
            .tracking(Theme.liveBadgeTracking)
            .foregroundStyle(Color(hex: "#292B31"))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: "#D2CEFD"), in: Capsule())
    }
}

/// A hairline rule that fades to transparent 24pt from each edge, matching the spec's
/// "Tracker row divider" note.
struct FadingDivider: View {
    var body: some View {
        GeometryReader { geo in
            let fade = min(24, geo.size.width / 4)
            let start = fade / geo.size.width
            let end = 1 - start
            LinearGradient(
                stops: [
                    .init(color: Theme.divider.opacity(0), location: 0),
                    .init(color: Theme.divider, location: start),
                    .init(color: Theme.divider, location: end),
                    .init(color: Theme.divider.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
        .frame(height: 1)
    }
}

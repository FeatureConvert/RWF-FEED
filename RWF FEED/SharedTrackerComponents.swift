//
//  SharedTrackerComponents.swift
//  RWF FEED
//
//  Small pieces shared between TrackerView (standings) and KillFeedView (kill log) —
//  both render guilds and need the same avatar/badge/divider treatment.
//

import SwiftUI
import UIKit

struct GuildAvatar: View {
    let guild: RaceGuild
    @State private var uiImage: UIImage?
    /// Bumping this restarts `load()` (it's keyed into the `.task(id:)` below) — used both to
    /// retry a failed load and to refetch if `guild.logo` itself changes.
    @State private var retryToken = 0
    private static let maxRetries = 2

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
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle().fill(colors.background)
                Text(initials)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.foreground)
            }
        }
        .frame(width: Theme.guildLogoDiameter, height: Theme.guildLogoDiameter)
        .clipShape(Circle())
        .task(id: "\(guild.logo)#\(retryToken)") {
            await load()
        }
    }

    /// Not AsyncImage: guild logos are served through Cloudflare Polish (raider.io's CDN),
    /// which content-negotiates on the Accept header and serves WebP instead of PNG once the
    /// client admits image/webp support — which iOS's networking stack does by default, but
    /// AsyncImage has no way to override the request headers it sends. A custom fetch with an
    /// explicit Accept forces PNG/JPEG back, sidestepping that entirely rather than depending
    /// on WebP decode support. Retries up to twice on any other failure (transient network
    /// blips), since AsyncImage-style loading has no built-in retry either.
    private func load() async {
        guard let url = URL(string: guild.logo) else { return }
        var request = URLRequest(url: url)
        request.setValue("image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        // These logos are served with a 1-year Cache-Control, and URLCache doesn't reliably
        // key on Vary: Accept — a WebP response cached under this URL before this Accept
        // header existed would otherwise keep being served forever regardless of what header
        // this request sends now. Bypass the read; the fresh (correctly-negotiated) response
        // still gets written back to the cache for next time.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data) {
            uiImage = image
            return
        }
        guard retryToken < Self.maxRetries else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        retryToken += 1
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

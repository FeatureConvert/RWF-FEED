//
//  SharedTrackerComponents.swift
//  RWF FEED
//
//  Small pieces shared between TrackerView (standings) and BossBreakdownView (boss list,
//  including its per-boss kill disclosure) — both render guilds and need the same
//  avatar/badge/divider treatment.
//

import SwiftUI
import UIKit

struct GuildAvatar: View {
    let guild: RaceGuild
    @State private var uiImage: UIImage?
    private static let maxRetries = 2
    /// Shared across every GuildAvatar instance app-wide, not per-row @State — without this,
    /// a guild's logo re-downloads from scratch every time its row scrolls out of and back
    /// into a List's visible region (List/SwiftUI reuse discards row @State on that boundary).
    /// Keyed by guild.logo since that's the only thing that can actually change per guild.
    @MainActor
    private static var imageCache: [String: UIImage] = [:]

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
        // `abs(Int.min)` traps — .magnitude has no such hole, since it's unsigned.
        Self.palette[Int(guild.id.magnitude % UInt(Self.palette.count))]
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
                    .font(.rwf(size: 12, weight: .bold))
                    .foregroundStyle(colors.foreground)
            }
        }
        .frame(width: Theme.guildLogoDiameter, height: Theme.guildLogoDiameter)
        .clipShape(Circle())
        .task(id: guild.logo) {
            await load()
        }
        // Purely decorative — the guild name it represents is always rendered as text
        // right next to it, so VoiceOver announcing "image" (or the initials as if they
        // were meaningful text) would just be noise ahead of the real content.
        .accessibilityHidden(true)
    }

    /// Not AsyncImage: guild logos are served through Cloudflare Polish (raider.io's CDN),
    /// which content-negotiates on the Accept header and serves WebP instead of PNG once the
    /// client admits image/webp support — which iOS's networking stack does by default, but
    /// AsyncImage has no way to override the request headers it sends. A custom fetch with an
    /// explicit Accept forces PNG/JPEG back, sidestepping that entirely rather than depending
    /// on WebP decode support.
    ///
    /// Checks the shared cache first, and retries (up to maxRetries, in a plain loop scoped to
    /// this one call — not external @State) only the underlying fetch on failure, so a
    /// transient blip on one URL can't leak retry budget onto a different URL this instance
    /// later loads.
    private func load() async {
        if let cached = Self.imageCache[guild.logo] {
            uiImage = cached
            return
        }
        guard let url = URL(string: guild.logo) else { return }
        var request = URLRequest(url: url)
        request.setValue("image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        for attempt in 0...Self.maxRetries {
            if let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data) {
                Self.imageCache[guild.logo] = image
                uiImage = image
                return
            }
            guard attempt < Self.maxRetries else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
        }
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
/// "WORLD FIRST" is only true when every region's guilds were considered — with a region
/// filter active, "1st" among the (region-filtered) rankings this badge sits next to only
/// means first *in that region*, and claiming otherwise would be factually wrong. Relabels
/// itself off the shared RegionFilter rather than needing every caller to pass region in.
struct WorldFirstBadge: View {
    @ObservedObject private var regionFilter = RegionFilter.shared

    private var label: String {
        regionFilter.region == .world ? "WORLD FIRST" : "\(regionFilter.region.label) FIRST"
    }

    var body: some View {
        Text(label)
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
        // A hairline rule between rows — decorative, not content.
        .accessibilityHidden(true)
    }
}

/// "Trending toward a kill" indicator — shown next to a live pull's percent on Bosses and
/// Heartbreak. An app-derived estimate (see PullTrend), so this is deliberately understated
/// rather than styled like a confident raider.io-sourced stat.
struct PullTrendLabel: View {
    let trend: PullTrend

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.isStalled ? "minus" : (trend.isImproving ? "arrow.down.right" : "arrow.up.right"))
                // The text alongside it already says the same thing in words ("Holding
                // steady" / "+2.1% in the last hour") — without this, VoiceOver announces
                // the SF Symbol's own name ("minus", "arrow down right") as a redundant,
                // confusing extra stop right before reading the text that explains it.
                .accessibilityHidden(true)
            Text(trend.isStalled ? "Holding steady" : String(format: "%+.1f%% in the last hour", trend.percentChange))
        }
        .font(.rwf(size: 11, weight: .medium))
        .foregroundStyle(trend.isImproving ? Theme.accentText : Theme.textSecondary)
    }
}

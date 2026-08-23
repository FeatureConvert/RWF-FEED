//
//  PostContent.swift
//  RWF FEED
//
//  Splits a post's raw HTML into an ordered sequence of renderable blocks — text runs,
//  standalone images, and iframe embeds (raider.io's own widgets, Twitch clips) — so
//  FeedPostRow can render each with the right native view instead of dropping media.
//

import Foundation
import SwiftUI

enum PostContentBlock {
    case text(AttributedString)
    case image(URL)
    case embed(EmbedInfo)
}

struct EmbedInfo {
    let url: URL
    let height: CGFloat
    let isTwitchClip: Bool
}

enum PostContent {
    static func parseBlocks(from html: String) -> [PostContentBlock] {
        var blocks: [PostContentBlock] = []

        let pattern = #"<iframe\b[^>]*>.*?</iframe>|<img\b[^>]*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            blocks.append(.text(HTMLContent.attributedString(from: html)))
            return blocks
        }

        let nsHtml = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))

        func appendText(_ range: NSRange) {
            guard range.length > 0 else { return }
            let chunk = nsHtml.substring(with: range)
            guard !chunk.strippingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let attributed = HTMLContent.attributedString(from: chunk)
            guard !attributed.characters.isEmpty else { return }
            blocks.append(.text(attributed))
        }

        var cursor = 0
        for match in matches {
            appendText(NSRange(location: cursor, length: match.range.location - cursor))
            let tag = nsHtml.substring(with: match.range)
            let lower = tag.lowercased()

            if lower.hasPrefix("<img"), let src = firstMatch(#"src="([^"]+)""#, in: tag), let url = URL(string: src) {
                blocks.append(.image(url))
            } else if lower.hasPrefix("<iframe"),
                      let rawSrc = firstMatch(#"src="([^"]+)""#, in: tag) {
                let src = rawSrc.replacingOccurrences(of: "&amp;", with: "&")
                if let url = URL(string: src) {
                    let isTwitch = src.contains("clips.twitch.tv")
                    let parsedHeight = firstMatch(#"height:\s*(\d+)px"#, in: tag).flatMap { Double($0) }
                    let height = CGFloat(parsedHeight ?? (isTwitch ? 220 : 260))
                    blocks.append(.embed(EmbedInfo(url: url, height: height, isTwitchClip: isTwitch)))
                }
            }
            cursor = match.range.location + match.range.length
        }
        appendText(NSRange(location: cursor, length: nsHtml.length - cursor))

        return blocks
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

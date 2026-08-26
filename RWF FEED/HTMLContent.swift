//
//  HTMLContent.swift
//  RWF FEED
//
//  Feed post bodies come back as raw HTML (links, embedded clips, images).
//  This turns that into an AttributedString SwiftUI can render, with tappable links.
//

import Foundation
import UIKit

enum HTMLContent {
    /// Converts HTML to an AttributedString with clickable links. Must run on the main thread
    /// — NSAttributedString's HTML importer is main-thread-only; moving this off it broke the
    /// Feed tab's rendering once already and had to be reverted. Callers should cache the
    /// result per post rather than move the parse itself elsewhere (see FeedPostRow).
    static func attributedString(from html: String) -> AttributedString {
        // Strip embeds we can't render inline (iframes, images). Leave real <br>/<div>/<p>
        // tags alone and let the HTML renderer do paragraph spacing itself — pre-converting
        // them to literal "\n" text backfires, since HTML collapses whitespace in text
        // content and silently eats those newlines, mashing every paragraph together.
        var cleaned = html
        cleaned = cleaned.replacingOccurrences(of: #"<iframe[^>]*>.*?</iframe>"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"<img[^>]*/?>"#, with: "", options: .regularExpression)

        // Embeds are often wrapped in one or more <div>s (e.g. a Twitch clip nested inside a
        // centering div); once the embed itself is gone those wrapper divs are empty but
        // still block elements, so they'd still force their own blank lines. Peel them off,
        // innermost first, until nothing empty is left.
        let emptyDiv = #"<div[^>]*>\s*</div>"#
        while let range = cleaned.range(of: emptyDiv, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        // Stripped embeds often leave behind runs of 3+ consecutive <br>s; cap that at one
        // blank line so removed embeds don't leave oversized gaps.
        cleaned = cleaned.replacingOccurrences(of: #"(?:\s*<br\s*/?>\s*){3,}"#, with: "<br/><br/>", options: .regularExpression)

        // 15pt scaled the same way the rest of the app's type scale is (Theme.font) — the
        // HTML importer has no concept of Dynamic Type on its own, so without this the post
        // body would be the one piece of text in the app permanently stuck at a fixed size
        // regardless of the user's text-size setting.
        let scaledSize = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15)).pointSize
        let wrapped = """
        <span style="font-family: -apple-system; font-size: \(scaledSize)px;">\(cleaned)</span>
        """
        guard let data = wrapped.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else {
            return AttributedString(html.strippingHTMLTags())
        }

        var attributed = AttributedString(ns)
        // NSAttributedString's HTML importer bakes in an explicit black foreground color,
        // which stays black in dark mode. Strip it so Text falls back to the adaptive
        // system label color (and links fall back to the adaptive accent tint).
        for run in attributed.runs {
            attributed[run.range].foregroundColor = nil
            attributed[run.range].backgroundColor = nil
        }

        // Trim trailing whitespace/newlines left over from stripped block elements.
        while let last = attributed.characters.last, last.isWhitespace {
            attributed.removeSubrange(attributed.index(beforeCharacter: attributed.endIndex)..<attributed.endIndex)
        }
        return attributed
    }
}

extension String {
    func strippingHTMLTags() -> String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

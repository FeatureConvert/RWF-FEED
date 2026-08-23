//
//  WowheadFeedParser.swift
//  RWF FEED
//
//  Parses Wowhead's public "retail" RSS feed (wowhead.com/news/rss/retail) — standard
//  RSS 2.0 with a media:content image per item, scoped to WoW retail news only (their RSS
//  also serves "diablo"/other-game categories under the same feed family, so "retail" is
//  the one that keeps this WoW-only).
//

import Foundation

enum WowheadFeedParser {
    static func parse(_ data: Data) -> [WowheadArticle] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.articles
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var articles: [WowheadArticle] = []

        private var currentElement = ""
        private var insideItem = false
        private var title = ""
        private var link = ""
        private var summaryText = ""
        private var pubDate = ""
        private var guid = ""
        private var imageURLString: String?

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return formatter
        }()

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            currentElement = elementName
            if elementName == "item" {
                insideItem = true
                title = ""
                link = ""
                summaryText = ""
                pubDate = ""
                guid = ""
                imageURLString = nil
            } else if elementName == "media:content", insideItem {
                imageURLString = attributeDict["url"]
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard insideItem else { return }
            switch currentElement {
            case "title": title += string
            case "link": link += string
            case "description": summaryText += string
            case "pubDate": pubDate += string
            case "guid": guid += string
            default: break
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName == "item" else { return }
            insideItem = false

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, let url = URL(string: trimmedLink) else { return }

            let trimmedGuid = guid.trimmingCharacters(in: .whitespacesAndNewlines)
            let publishedAt = Self.dateFormatter.date(from: pubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Date()

            articles.append(
                WowheadArticle(
                    guid: trimmedGuid.isEmpty ? trimmedLink : trimmedGuid,
                    title: trimmedTitle.strippingHTMLTags(),
                    link: url,
                    summary: summaryText.strippingHTMLTags().strippingWowheadContinueReadingSuffix(),
                    imageURL: imageURLString.flatMap { URL(string: $0) },
                    publishedAt: publishedAt
                )
            )
        }
    }
}

private extension String {
    /// Wowhead's RSS `<description>` always ends with a "Continue reading »" link back to the
    /// full article. `strippingHTMLTags()` correctly removes the `<a>` markup but leaves that
    /// link's text run directly on to the preceding sentence with no separating space (e.g.
    /// "...high priority issue.Continue reading »") — stripped here since it's Wowhead-specific
    /// boilerplate, not part of the actual summary.
    func strippingWowheadContinueReadingSuffix() -> String {
        let suffix = "Continue reading »"
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

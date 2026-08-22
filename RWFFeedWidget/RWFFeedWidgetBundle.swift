//
//  RWFFeedWidgetBundle.swift
//  RWFFeedWidget
//

import WidgetKit
import SwiftUI

@main
struct RWFFeedWidgetBundle: WidgetBundle {
    var body: some Widget {
        RWFFeedWidget()
    }
}

struct RWFFeedWidget: Widget {
    let kind: String = "RWFFeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RWFTimelineProvider()) { entry in
            RWFFeedWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.background }
        }
        .configurationDisplayName("Boss Progress")
        .description("The furthest boss currently being pulled in the Race to World First, and who's closest.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

//
//  RWFFeedComplicationBundle.swift
//  RWFFeedWatchWidget
//

import WidgetKit
import SwiftUI

@main
struct RWFFeedComplicationBundle: WidgetBundle {
    var body: some Widget {
        RWFFeedComplication()
    }
}

struct RWFFeedComplication: Widget {
    let kind: String = "RWFFeedComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Boss Progress")
        .description("The furthest boss currently being pulled, and who's closest.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}

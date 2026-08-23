//
//  ComplicationProvider.swift
//  RWFFeedWatchWidget
//

import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let boss: WatchBossState?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), boss: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview {
            completion(ComplicationEntry(date: Date(), boss: .placeholder))
            return
        }
        Task {
            completion(ComplicationEntry(date: Date(), boss: await RWFWatchData.fetchCurrentBoss()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        Task {
            let entry = ComplicationEntry(date: Date(), boss: await RWFWatchData.fetchCurrentBoss())
            // watchOS budgets complication refreshes even more tightly than iOS Home Screen
            // widgets — this is a request, not a guarantee of actual cadence.
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

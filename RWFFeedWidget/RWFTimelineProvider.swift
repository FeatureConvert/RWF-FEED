//
//  RWFTimelineProvider.swift
//  RWFFeedWidget
//

import WidgetKit

struct RWFTimelineEntry: TimelineEntry {
    let date: Date
    let boss: WidgetBossState?
}

struct RWFTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RWFTimelineEntry {
        RWFTimelineEntry(date: Date(), boss: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RWFTimelineEntry) -> Void) {
        if context.isPreview {
            completion(RWFTimelineEntry(date: Date(), boss: .placeholder))
            return
        }
        Task {
            completion(RWFTimelineEntry(date: Date(), boss: await RWFWidgetData.fetchCurrentBoss()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RWFTimelineEntry>) -> Void) {
        Task {
            let entry = RWFTimelineEntry(date: Date(), boss: await RWFWidgetData.fetchCurrentBoss())
            // WidgetKit's actual refresh cadence is system-budgeted and usually coarser than
            // this during normal use — this is a request, not a guarantee.
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

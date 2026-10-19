import SwiftUI
import WidgetKit

/// Timeline entry wrapping the app-written snapshot (nil = the app hasn't produced one yet).
struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?

    /// True when the snapshot belongs to an earlier day (show "Open Vigil to update").
    func isStale(calendar: Calendar = .current) -> Bool {
        guard let snapshot else { return true }
        return !calendar.isDate(snapshot.day, inSameDayAs: date)
    }
}

/// Reads the snapshot from the App Group. The app calls `WidgetCenter.reloadAllTimelines()`
/// after writing, so the timeline only needs a safety refresh at the next midnight.
struct SnapshotTimelineProvider: TimelineProvider {
    var store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder() : (store.load() ?? .placeholder())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let entry = SnapshotEntry(date: now, snapshot: store.load())
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

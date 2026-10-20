import SwiftUI
import WidgetKit

/// Timeline entry wrapping what the widget should show at `date`.
struct SnapshotEntry: TimelineEntry {
    var date: Date
    var state: WidgetDisplayState

    init(date: Date, snapshot: WidgetSnapshot?, groupAvailable: Bool = true) {
        self.date = date
        self.state = WidgetSnapshot.displayState(snapshot: snapshot, at: date, groupAvailable: groupAvailable)
    }

    /// Snapshot to render, or nil when the widget should ask the user to open Vigil.
    var snapshot: WidgetSnapshot? {
        if case .ready(let snapshot) = state { snapshot } else { nil }
    }
}

/// Reads the snapshot from the App Group. The app calls `WidgetCenter.reloadAllTimelines()` after writing,
/// so the provider only schedules (a) a flip to "Open Vigil to update" when the snapshot turns 36 h old and
/// (b) a safety refresh a few hours out.
struct SnapshotTimelineProvider: TimelineProvider {
    /// Safety refresh interval when the app does not push a reload.
    static let refreshInterval: TimeInterval = 3 * 3600

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(SnapshotEntry(date: .now, snapshot: .placeholder()))
        } else {
            completion(SnapshotEntry(date: .now, snapshot: Self.load(), groupAvailable: Self.groupAvailable))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Self.timeline(now: .now, snapshot: Self.load(), groupAvailable: Self.groupAvailable))
    }

    static var groupAvailable: Bool { AppGroup.containerURL != nil }

    static func load() -> WidgetSnapshot? {
        groupAvailable ? WidgetSnapshotStore().load() : nil
    }

    /// Entries: now, the next midnight (yesterday's scores flip to "Open Vigil to update") and the 36 h
    /// staleness flip, whichever lie in the future, ascending.
    static func timeline(now: Date, snapshot: WidgetSnapshot?, groupAvailable: Bool,
                         calendar: Calendar = .autoupdatingCurrent) -> Timeline<SnapshotEntry> {
        var entries = [SnapshotEntry(date: now, snapshot: snapshot, groupAvailable: groupAvailable)]
        if groupAvailable, let snapshot {
            let flips = Set([WidgetSnapshot.nextDayStart(after: now, calendar: calendar), snapshot.staleDate])
                .filter { $0 > now }
                .sorted()
            entries += flips.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshInterval)))
    }
}

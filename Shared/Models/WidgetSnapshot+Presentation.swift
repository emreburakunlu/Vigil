import Foundation

// Additive helpers for `WidgetSnapshot` (freshness and presentation). The stored payload is unchanged.

/// What a widget should render for a given snapshot.
enum WidgetDisplayState: Equatable, Sendable {
    /// Fresh data: render the scores.
    case ready(WidgetSnapshot)
    /// Missing / stale snapshot or App Group unavailable: render "Open Vigil to update".
    case needsUpdate
}

extension WidgetSnapshot {
    /// A snapshot older than this is not shown (the widget asks the user to open Vigil).
    static let staleAfter: TimeInterval = 36 * 3600

    /// `true` when the snapshot was generated more than `staleAfter` before `date`.
    /// A snapshot slightly from the future (clock changes) counts as fresh.
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > Self.staleAfter
    }

    /// The moment this snapshot turns stale; used to schedule a timeline entry that flips the widget.
    var staleDate: Date { generatedAt.addingTimeInterval(Self.staleAfter) }

    /// Whether the snapshot's scores belong to the calendar day containing `date`.
    func isForDay(of date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    /// Resolves what to show. `groupAvailable == false` (no App Group entitlement) always needs an update,
    /// because the app's data cannot be shared with the widget. Yesterday's scores are never shown as
    /// today's: after midnight the widget asks the user to open Vigil until the app writes a new snapshot.
    static func displayState(snapshot: WidgetSnapshot?, at date: Date, groupAvailable: Bool = true,
                             calendar: Calendar = .autoupdatingCurrent) -> WidgetDisplayState {
        guard groupAvailable, let snapshot, !snapshot.isStale(at: date), snapshot.isForDay(of: date, calendar: calendar) else {
            return .needsUpdate
        }
        return .ready(snapshot)
    }

    /// Start of the day after `date`; the timeline flips there.
    static func nextDayStart(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Short readiness label under the Recovery ring ("Push day").
    var readinessLabel: String? {
        switch readiness {
        case .push: "Push day"
        case .maintain: "Maintain"
        case .takeItEasy: "Take it easy"
        case nil: nil
        }
    }

    /// Recovery band, derived from the percentage when the stored band is missing.
    var resolvedRecoveryBand: RecoveryBand? {
        recoveryBand ?? recoveryPercent.map { RecoveryBand(percent: $0) }
    }

    /// Weekly running progress, 0...1 (0 when there is no goal).
    var runProgress: Double {
        weeklyRunGoalMeters > 0 ? min(max(weeklyRunDistanceMeters / weeklyRunGoalMeters, 0), 1) : 0
    }
}

import Foundation
import Observation
import SwiftUI

/// State of the Today dashboard: the selected day, the day strip and the loaded `DayOverview`.
@MainActor
@Observable
final class TodayModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var phase: Phase = .loading
    /// Overview of `loadedDay`. May lag behind `selection` while the next day loads.
    private(set) var overview: DayOverview?
    private(set) var today: LocalDay
    private(set) var window: TodayDayWindow
    /// Recovery percent per strip day, for the score dots.
    private(set) var recoveryByDay: [LocalDay: Int] = [:]
    private let calendar: Calendar

    var selection: LocalDay

    init(today: LocalDay = .today(), calendar: Calendar = .current) {
        self.today = today
        self.calendar = calendar
        self.selection = today
        self.window = TodayDayWindow(end: today, calendar: calendar)
    }

    var isToday: Bool { selection == today }
    var canStepForward: Bool { selection < today }

    /// True while `overview` belongs to another day than the selection (shown redacted).
    var isStale: Bool { overview?.day != selection }

    // MARK: Navigation

    func step(by delta: Int) {
        select(TodayDayWindow.step(selection, by: delta, today: today, calendar: calendar))
    }

    func select(_ day: LocalDay) {
        let clamped = min(day, today)
        guard clamped != selection else { return }
        selection = clamped
        window = TodayDayWindow.containing(clamped, today: today, calendar: calendar)
    }

    // MARK: Loading

    /// Follows `AppContainer.currentDay`. A selection on the old today moves to the new today and the strip slides with it.
    func rollOver(to newToday: LocalDay) {
        guard newToday != today else { return }
        let old = today
        today = newToday
        selection = selection == old ? newToday : min(selection, newToday)
        window = TodayDayWindow.containing(selection, today: newToday, calendar: calendar)
    }

    func load(_ repository: VigilRepository) async {
        let day = selection
        if overview == nil { phase = .loading }
        do {
            let result = try await repository.dayOverview(for: day)
            guard !Task.isCancelled, day == selection else { return }
            overview = result
            recoveryByDay[day] = result.recovery?.value
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, day == selection else { return }
            phase = .failed
        }
    }

    /// Fills the strip dots with one ranged read of the strip window (missing days are built in one batch).
    func loadDots(_ repository: VigilRepository) async {
        let days = window.days
        guard let first = days.first, let last = days.last else { return }
        guard let summaries = try? await repository.ensuredSummaries(from: first, through: last), !Task.isCancelled else { return }
        for summary in summaries where days.contains(summary.day) {
            if let recovery = summary.recovery { recoveryByDay[summary.day] = recovery.value }
        }
    }

    // MARK: Derived

    func stripItems() -> [DayStripItem] {
        window.days.map { day in
            let percent = recoveryByDay[day]
            return DayStripItem(
                day: day,
                dot: percent.map { Color.vRecoveryBand(RecoveryBand(percent: $0)) },
                isEnabled: day <= today,
                accessibilityValue: percent.map { String(localized: "recovery \($0) percent") }
            )
        }
    }
}

import Foundation

extension VigilRepository {
    /// Primary nights (with bedtime and wake times) for `start...end`, oldest first.
    /// `sleepHistory` only carries asleep time and score, so the bedtime/wake-time consistency trend needs this.
    func primarySleepNights(from start: LocalDay, through end: LocalDay) async throws -> [SleepNight] {
        try await dataSource
            .sleepNights(in: LocalDay.interval(from: start, through: end, calendar: calendar))
            .filter(\.isPrimary)
    }
}

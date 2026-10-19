import Foundation
@testable import Vigil

enum TestSupport {
    /// Gregorian calendar fixed to UTC so tests don't depend on the machine's time zone.
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday 19 Oct 2026, 12:00 UTC — the date used throughout the design.
    static let referenceDate: Date = {
        utc.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
    }()

    static let enUS = Locale(identifier: "en_US")
}

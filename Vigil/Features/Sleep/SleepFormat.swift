import Foundation

/// Small text helpers shared by the Sleep screens. Numbers and units always come from `VigilFormatter`.
enum SleepFormat {
    private static func style(_ base: Date.FormatStyle, calendar: Calendar) -> Date.FormatStyle {
        var style = base
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .autoupdatingCurrent
        return style
    }

    /// `"Sun 18 → Mon 19 Oct"` for the night that ended on `day`.
    static func nightRange(for day: LocalDay, calendar: Calendar) -> String {
        let first = style(Date.FormatStyle().weekday(.abbreviated).day(), calendar: calendar)
        let second = style(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated), calendar: calendar)
        let start = day.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let end = day.startDate(in: calendar)
        return "\(start.formatted(first)) → \(end.formatted(second))"
    }

    /// `"Wednesday"`, the wake-up weekday, used as the title of past nights.
    static func weekdayTitle(for day: LocalDay, calendar: Calendar) -> String {
        day.startDate(in: calendar).formatted(style(Date.FormatStyle().weekday(.wide), calendar: calendar))
    }

    /// `"Oct 13"`.
    static func shortDate(_ day: LocalDay, calendar: Calendar) -> String {
        day.startDate(in: calendar).formatted(style(Date.FormatStyle().month(.abbreviated).day(), calendar: calendar))
    }

    /// `"October 2026"`.
    static func monthTitle(_ day: LocalDay, calendar: Calendar) -> String {
        day.startDate(in: calendar).formatted(style(Date.FormatStyle().month(.wide).year(), calendar: calendar))
    }

    /// `"Wed 14"`-style VoiceOver date, e.g. `"Wednesday, 14 October"`.
    static func spokenDate(_ day: LocalDay, calendar: Calendar) -> String {
        day.startDate(in: calendar).formatted(style(Date.FormatStyle().weekday(.wide).day().month(.wide), calendar: calendar))
    }

    /// `"8h"` for whole hours, `"7h 30m"` otherwise.
    static func targetText(_ seconds: TimeInterval, formatter: VigilFormatter) -> String {
        let text = formatter.duration(seconds)
        return text.hasSuffix(" 00m") ? String(text.dropLast(4)) : text
    }

    /// Shortfall/surplus amount: `"18 min"` under an hour, `"1h 10m"` above.
    static func gapText(_ seconds: TimeInterval, formatter: VigilFormatter) -> String {
        let magnitude = abs(seconds)
        return magnitude < 3600 ? formatter.duration(magnitude, style: .minutes) : formatter.duration(magnitude)
    }

    /// `"18 min short of your 8h target"`.
    static func targetCaption(difference: TimeInterval, target: TimeInterval, formatter: VigilFormatter) -> String {
        let targetText = targetText(target, formatter: formatter)
        let gap = gapText(difference, formatter: formatter)
        if abs(difference) < 60 { return String(localized: "Right on your \(targetText) target") }
        return difference < 0
            ? String(localized: "\(gap) short of your \(targetText) target")
            : String(localized: "\(gap) over your \(targetText) target")
    }

    /// Minutes after 18:00 local on the evening of `date` (the engine's bedtime axis; wraps at midnight correctly).
    static func minutesAfterSix(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes - 18 * 60 + 24 * 60).truncatingRemainder(dividingBy: 24 * 60)
    }
}

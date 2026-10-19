import Foundation

/// A number and its unit, kept separate because the design renders them in different styles
/// ("8.04" large + "km" small). Use `text` when a single string is needed.
struct FormattedValue: Hashable, Sendable, CustomStringConvertible {
    /// The localized numeric part, e.g. `"8.04"`, `"5:16"`, `"+0.21"`.
    var value: String
    /// The unit symbol, e.g. `"km"`, `"/km"`, `"°C"`. May be empty.
    var unit: String

    /// `"8.04 km"`, `"5:16 /km"`, `"78%"` (no space before `%`).
    var text: String {
        if unit.isEmpty { return value }
        if unit == "%" { return value + unit }
        return "\(value) \(unit)"
    }

    var description: String { text }
}

/// How a duration is written.
enum DurationStyle: Sendable {
    /// `"7h 42m"`, `"8h 06m"`, `"24m"` — sleep, totals, zone times.
    case hoursMinutes
    /// `"42:18"`, `"1:07:24"` — workout elapsed time.
    case clock
    /// `"1:38"` — hours:minutes, e.g. weekly running time.
    case hoursMinutesClock
    /// `"58 min"` — workout length in lists.
    case minutes
}

/// Unit conversion constants (exact definitions).
enum UnitConversion {
    static let metersPerKilometer = 1_000.0
    static let metersPerMile = 1_609.344
    static let kilogramsPerPound = 0.453_592_37
    static let metersPerFoot = 0.304_8
    static let centimetersPerInch = 2.54
}

/// The single place that turns canonical metric values into display strings.
///
/// Feature code must never hard-code unit symbols or do unit maths; ask the formatter.
/// Canonical inputs: metres, kilograms, seconds, seconds-per-kilometre, °C, kcal, bpm.
/// Use `settings.formatter` (app) or `VigilFormatter(units: snapshot.units)` (widget).
struct VigilFormatter: Sendable {
    var units: UnitSystem
    var locale: Locale

    init(units: UnitSystem = .metric, locale: Locale = .autoupdatingCurrent) {
        self.units = units
        self.locale = locale
    }

    // MARK: Distance

    /// `"km"` or `"mi"`.
    var distanceUnit: String { units == .metric ? "km" : "mi" }

    /// Metres → kilometres or miles (numeric).
    func displayDistance(meters: Double) -> Double {
        meters / (units == .metric ? UnitConversion.metersPerKilometer : UnitConversion.metersPerMile)
    }

    /// Kilometres or miles → metres (for goal steppers that edit in display units).
    func meters(fromDisplayDistance value: Double) -> Double {
        value * (units == .metric ? UnitConversion.metersPerKilometer : UnitConversion.metersPerMile)
    }

    /// `"8.04 km"` / `"5.00 mi"`.
    func distance(meters: Double, fractionDigits: Int = 2) -> FormattedValue {
        FormattedValue(value: number(displayDistance(meters: meters), fractionDigits: fractionDigits), unit: distanceUnit)
    }

    // MARK: Pace

    /// `"/km"` or `"/mi"`.
    var paceUnit: String { "/" + distanceUnit }

    /// Seconds per km → seconds per display unit.
    func displayPace(secondsPerKilometer: Double) -> Double {
        units == .metric ? secondsPerKilometer : secondsPerKilometer * UnitConversion.metersPerMile / UnitConversion.metersPerKilometer
    }

    /// `"5:16 /km"` / `"8:28 /mi"`. Non-finite or non-positive input renders `"–:––"`.
    func pace(secondsPerKilometer: Double) -> FormattedValue {
        let seconds = displayPace(secondsPerKilometer: secondsPerKilometer)
        guard seconds.isFinite, seconds > 0 else { return FormattedValue(value: "–:––", unit: paceUnit) }
        let total = Int(seconds.rounded())
        return FormattedValue(value: String(format: "%d:%02d", total / 60, total % 60), unit: paceUnit)
    }

    /// Pace difference, e.g. `"12 s/km"` (absolute value; callers phrase faster/slower).
    func paceDifference(secondsPerKilometer: Double) -> FormattedValue {
        let seconds = abs(displayPace(secondsPerKilometer: secondsPerKilometer))
        return FormattedValue(value: number(seconds, fractionDigits: 0), unit: "s" + paceUnit)
    }

    // MARK: Weight

    /// `"kg"` or `"lb"`.
    var weightUnit: String { units == .metric ? "kg" : "lb" }

    func displayWeight(kilograms: Double) -> Double {
        units == .metric ? kilograms : kilograms / UnitConversion.kilogramsPerPound
    }

    func kilograms(fromDisplayWeight value: Double) -> Double {
        units == .metric ? value : value * UnitConversion.kilogramsPerPound
    }

    /// `"78.4 kg"` / `"172.8 lb"`.
    func weight(kilograms: Double, fractionDigits: Int = 1) -> FormattedValue {
        FormattedValue(value: number(displayWeight(kilograms: kilograms), fractionDigits: fractionDigits), unit: weightUnit)
    }

    /// Signed weight change, e.g. `"−1.2 kg"`.
    func weightChange(kilograms: Double, fractionDigits: Int = 1) -> FormattedValue {
        FormattedValue(value: signed(displayWeight(kilograms: kilograms), fractionDigits: fractionDigits), unit: weightUnit)
    }

    // MARK: Elevation & short lengths

    /// `"m"` or `"ft"`.
    var elevationUnit: String { units == .metric ? "m" : "ft" }

    /// `"46 m"` / `"151 ft"`.
    func elevation(meters: Double) -> FormattedValue {
        FormattedValue(value: number(displayElevation(meters: meters), fractionDigits: 0), unit: elevationUnit)
    }

    /// `"+46 m"`, `"−40 m"`.
    func elevationChange(meters: Double) -> FormattedValue {
        FormattedValue(value: signed(displayElevation(meters: meters), fractionDigits: 0), unit: elevationUnit)
    }

    func displayElevation(meters: Double) -> Double {
        units == .metric ? meters : meters / UnitConversion.metersPerFoot
    }

    /// Stride length: `"1.10 m"` / `"3.61 ft"`.
    func strideLength(meters: Double) -> FormattedValue {
        FormattedValue(value: number(displayElevation(meters: meters), fractionDigits: 2), unit: elevationUnit)
    }

    /// Vertical oscillation: `"8.6 cm"` / `"3.4 in"`.
    func verticalOscillation(centimeters: Double) -> FormattedValue {
        let value = units == .metric ? centimeters : centimeters / UnitConversion.centimetersPerInch
        return FormattedValue(value: number(value, fractionDigits: 1), unit: units == .metric ? "cm" : "in")
    }

    // MARK: Temperature

    /// Temperature *difference* (no offset): `"+0.21 °C"` / `"+0.38 °F"`.
    func temperatureDelta(celsius: Double, fractionDigits: Int = 2) -> FormattedValue {
        let value = units == .metric ? celsius : celsius * 9 / 5
        return FormattedValue(value: signed(value, fractionDigits: fractionDigits), unit: units == .metric ? "°C" : "°F")
    }

    // MARK: Physiology & activity (unit-system independent)

    /// `"412 kcal"`.
    func energy(kilocalories: Double) -> FormattedValue {
        FormattedValue(value: number(kilocalories, fractionDigits: 0), unit: "kcal")
    }

    /// `"152 bpm"`.
    func heartRate(bpm: Double) -> FormattedValue {
        FormattedValue(value: number(bpm, fractionDigits: 0), unit: "bpm")
    }

    /// `"68 ms"` (HRV SDNN).
    func heartRateVariability(milliseconds: Double) -> FormattedValue {
        FormattedValue(value: number(milliseconds, fractionDigits: 0), unit: "ms")
    }

    /// `"14.6 br/min"`.
    func respiratoryRate(breathsPerMinute: Double) -> FormattedValue {
        FormattedValue(value: number(breathsPerMinute, fractionDigits: 1), unit: "br/min")
    }

    /// `"97%"` — input is a percentage 0–100 (not a 0–1 fraction).
    func oxygenSaturation(percent: Double) -> FormattedValue {
        FormattedValue(value: number(percent, fractionDigits: 0), unit: "%")
    }

    /// `"47.8 mL/kg/min"`.
    func vo2Max(_ value: Double) -> FormattedValue {
        FormattedValue(value: number(value, fractionDigits: 1), unit: "mL/kg/min")
    }

    /// `"172 spm"`.
    func cadence(stepsPerMinute: Double) -> FormattedValue {
        FormattedValue(value: number(stepsPerMinute, fractionDigits: 0), unit: "spm")
    }

    /// `"248 ms"`.
    func groundContactTime(milliseconds: Double) -> FormattedValue {
        FormattedValue(value: number(milliseconds, fractionDigits: 0), unit: "ms")
    }

    /// `"268 W"`.
    func power(watts: Double) -> FormattedValue {
        FormattedValue(value: number(watts, fractionDigits: 0), unit: "W")
    }

    /// `"11,284"` (locale grouping).
    func steps(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic).locale(locale))
    }

    /// `"78%"`.
    func percent(_ value: Int) -> FormattedValue {
        FormattedValue(value: number(Double(value), fractionDigits: 0), unit: "%")
    }

    /// Signed percentage change: `"+12%"`, `"−5%"`.
    func percentChange(_ value: Double, fractionDigits: Int = 0) -> FormattedValue {
        FormattedValue(value: signed(value, fractionDigits: fractionDigits), unit: "%")
    }

    // MARK: Durations

    /// Formats a duration in seconds. Negative input is treated as zero.
    func duration(_ seconds: TimeInterval, style: DurationStyle = .hoursMinutes) -> String {
        Self.duration(seconds, style: style)
    }

    /// Locale-independent duration formatting (see `DurationStyle`).
    static func duration(_ seconds: TimeInterval, style: DurationStyle = .hoursMinutes) -> String {
        let safe = seconds.isFinite ? max(0, seconds) : 0
        switch style {
        case .hoursMinutes:
            let totalMinutes = Int((safe / 60).rounded())
            let h = totalMinutes / 60, m = totalMinutes % 60
            return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
        case .clock:
            let total = Int(safe.rounded())
            let h = total / 3600, m = (total % 3600) / 60, s = total % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        case .hoursMinutesClock:
            let totalMinutes = Int((safe / 60).rounded())
            return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
        case .minutes:
            return "\(Int((safe / 60).rounded())) min"
        }
    }

    /// Time of day in the user's locale/24h preference, e.g. `"22:58"` or `"10:58 PM"`.
    func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    // MARK: Numbers

    /// Locale-aware fixed-precision number.
    func number(_ value: Double, fractionDigits: Int) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// Number with an explicit sign, using a true minus sign (U+2212) as in the design: `"+12"`, `"−3"`.
    /// Values that round to zero render without a sign.
    func signed(_ value: Double, fractionDigits: Int) -> String {
        guard value.isFinite else { return "–" }
        let magnitude = number(abs(value), fractionDigits: fractionDigits)
        let roundsToZero = number(0, fractionDigits: fractionDigits) == magnitude
        if roundsToZero { return magnitude }
        return (value < 0 ? "\u{2212}" : "+") + magnitude
    }
}

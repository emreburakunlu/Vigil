import Foundation
import Testing
@testable import Vigil

@Suite("VigilFormatter")
struct FormatterTests {
    let metric = VigilFormatter(units: .metric, locale: TestSupport.enUS)
    let imperial = VigilFormatter(units: .imperial, locale: TestSupport.enUS)

    @Test func distance() {
        #expect(metric.distance(meters: 8_040).text == "8.04 km")
        #expect(imperial.distance(meters: 8_046.72).text == "5.00 mi")
        #expect(metric.distance(meters: 25_000, fractionDigits: 0).text == "25 km")
        #expect(imperial.distance(meters: 25_000, fractionDigits: 1).text == "15.5 mi")
        #expect(abs(imperial.meters(fromDisplayDistance: 1) - 1_609.344) < 0.0001)
    }

    @Test func pace() {
        #expect(metric.pace(secondsPerKilometer: 316).text == "5:16 /km")
        // 316 s/km × 1.609344 = 508.55 s/mi → 8:29
        #expect(imperial.pace(secondsPerKilometer: 316).text == "8:29 /mi")
        #expect(metric.pace(secondsPerKilometer: 299.6).value == "5:00")
        #expect(metric.pace(secondsPerKilometer: 0).value == "–:––")
        #expect(metric.pace(secondsPerKilometer: .infinity).value == "–:––")
        #expect(metric.paceDifference(secondsPerKilometer: -12).text == "12 s/km")
    }

    @Test func weight() {
        #expect(metric.weight(kilograms: 78.4).text == "78.4 kg")
        #expect(imperial.weight(kilograms: 78.4).text == "172.8 lb")
        #expect(metric.weightChange(kilograms: -1.2).text == "\u{2212}1.2 kg")
        #expect(abs(imperial.kilograms(fromDisplayWeight: 172.8) - 78.38) < 0.01)
    }

    @Test func elevationAndLengths() {
        #expect(metric.elevation(meters: 46).text == "46 m")
        #expect(imperial.elevation(meters: 46).text == "151 ft")
        #expect(metric.elevationChange(meters: -40).text == "\u{2212}40 m")
        #expect(metric.elevationChange(meters: 46).text == "+46 m")
        #expect(metric.strideLength(meters: 1.1).text == "1.10 m")
        #expect(imperial.strideLength(meters: 1.1).text == "3.61 ft")
        #expect(metric.verticalOscillation(centimeters: 8.6).text == "8.6 cm")
        #expect(imperial.verticalOscillation(centimeters: 8.6).text == "3.4 in")
    }

    @Test func temperatureDelta() {
        #expect(metric.temperatureDelta(celsius: 0.21).text == "+0.21 °C")
        #expect(imperial.temperatureDelta(celsius: 0.21).text == "+0.38 °F")
        #expect(metric.temperatureDelta(celsius: -0.1).text == "\u{2212}0.10 °C")
        #expect(metric.temperatureDelta(celsius: 0.001).text == "0.00 °C")
    }

    @Test func physiology() {
        #expect(metric.heartRate(bpm: 152.4).text == "152 bpm")
        #expect(metric.heartRateVariability(milliseconds: 68).text == "68 ms")
        #expect(metric.respiratoryRate(breathsPerMinute: 14.6).text == "14.6 br/min")
        #expect(metric.oxygenSaturation(percent: 97).text == "97%")
        #expect(metric.percent(78).text == "78%")
        #expect(metric.percentChange(12).text == "+12%")
        #expect(metric.energy(kilocalories: 412.3).text == "412 kcal")
        #expect(metric.steps(11_284) == "11,284")
        #expect(metric.format(.vo2Max, 47.8).text == "47.8 mL/kg/min")
        #expect(imperial.format(.bodyMass, 78.4).text == "172.8 lb")
    }

    @Test func durations() {
        #expect(VigilFormatter.duration(7 * 3600 + 42 * 60) == "7h 42m")
        #expect(VigilFormatter.duration(8 * 3600 + 6 * 60) == "8h 06m")
        #expect(VigilFormatter.duration(24 * 60) == "24m")
        #expect(VigilFormatter.duration(-5) == "0m")
        #expect(VigilFormatter.duration(42 * 60 + 18, style: .clock) == "42:18")
        #expect(VigilFormatter.duration(3600 + 7 * 60 + 24, style: .clock) == "1:07:24")
        #expect(VigilFormatter.duration(98 * 60, style: .hoursMinutesClock) == "1:38")
        #expect(VigilFormatter.duration(58 * 60 + 12, style: .minutes) == "58 min")
    }

    @Test func signedNumbers() {
        #expect(metric.signed(12, fractionDigits: 0) == "+12")
        #expect(metric.signed(-3, fractionDigits: 0) == "\u{2212}3")
        #expect(metric.signed(-0.2, fractionDigits: 0) == "0")
        #expect(metric.signed(.nan, fractionDigits: 0) == "–")
    }

    @Test func localeAwareDecimalSeparator() {
        let german = VigilFormatter(units: .metric, locale: Locale(identifier: "de_DE"))
        #expect(german.distance(meters: 8_040).text == "8,04 km")
    }
}

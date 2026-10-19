import Foundation
import Testing
@testable import Vigil

@Suite("HealthKit · series & vitals")
struct HealthKitSeriesTests {
    let calendar = TestSupport.utc
    let t0 = TestSupport.referenceDate

    func series(_ values: [Double], step: TimeInterval = 1) -> [MetricSample] {
        values.enumerated().map { MetricSample(date: t0.addingTimeInterval(Double($0.offset) * step), value: $0.element) }
    }

    // MARK: Downsampling

    @Test func downsampleLeavesShortSeriesUntouched() {
        let short = series([1, 2, 3])
        #expect(SeriesDownsampler.downsample(short, maxPoints: 10) == short)
        #expect(SeriesDownsampler.downsample([], maxPoints: 10).isEmpty)
    }

    @Test func downsampleLongSeries() throws {
        let long = series((0..<10_000).map { Double($0 % 100) })
        let reduced = SeriesDownsampler.downsample(long, maxPoints: 200)
        #expect(reduced.count <= 200)
        #expect(reduced.count > 150)
        #expect(reduced.first == long.first)
        #expect(reduced.last == long.last)
        #expect(zip(reduced, reduced.dropFirst()).allSatisfy { $0.date <= $1.date })
        let mean = try #require(RunSeriesMath.mean(reduced.dropFirst().dropLast().map { $0 }))
        #expect(abs(mean - 49.5) < 1)
    }

    @Test func downsampleConstantSeriesKeepsValue() {
        let reduced = SeriesDownsampler.downsample(series(Array(repeating: 150, count: 5_000)), maxPoints: 100)
        #expect(reduced.allSatisfy { $0.value == 150 })
    }

    // MARK: Pace, distance, cadence

    @Test func paceFromSpeed() {
        #expect(RunSeriesMath.pace(speedMetersPerSecond: 4) == 250)
        #expect(RunSeriesMath.pace(speedMetersPerSecond: 0.2) == nil)
        let pace = RunSeriesMath.paceSeries(fromSpeed: series([3.333_333_33, 0, 4]))
        #expect(pace.count == 2)
        #expect(abs(pace[0].value - 300) < 0.01)
    }

    @Test func cumulativeDistanceFromBuckets() {
        let buckets = (0..<4).map { i in
            QuantityBucket(interval: DateInterval(start: t0.addingTimeInterval(Double(i) * 5), duration: 5), value: i == 2 ? 0 : 15)
        }
        let cumulative = RunSeriesMath.cumulativeDistance(fromBuckets: buckets.reversed())
        #expect(cumulative.map(\.value) == [0, 15, 30, 45])
        #expect(cumulative.first?.date == t0)
        #expect(cumulative.last?.date == t0.addingTimeInterval(20))
        #expect(RunSeriesMath.cumulativeDistance(fromBuckets: []).isEmpty)
    }

    @Test func paceFromCumulativeDistance() throws {
        // 4 m/s for 2 minutes, sampled every 5 s → 250 s/km.
        let distance = series((0...24).map { Double($0) * 20 }, step: 5)
        let pace = RunSeriesMath.paceSeries(fromCumulativeDistance: distance)
        #expect(pace.count == 24)
        #expect(pace.allSatisfy { abs($0.value - 250) < 0.001 })
        #expect(RunSeriesMath.paceSeries(fromCumulativeDistance: []).isEmpty)
    }

    @Test func cadenceClipsPartialBuckets() {
        let workout = DateInterval(start: t0.addingTimeInterval(30), duration: 150) // 0:30 → 3:00
        let buckets = [
            QuantityBucket(interval: DateInterval(start: t0, duration: 60), value: 85),                       // 30 s inside
            QuantityBucket(interval: DateInterval(start: t0.addingTimeInterval(60), duration: 60), value: 170),
            QuantityBucket(interval: DateInterval(start: t0.addingTimeInterval(120), duration: 60), value: 0), // paused
        ]
        let cadence = RunSeriesMath.cadenceSeries(fromStepBuckets: buckets, within: workout)
        #expect(cadence.map(\.value) == [170, 170])
    }

    @Test func routeFilteringAndElevation() {
        let route = [
            RouteLocation(timestamp: t0.addingTimeInterval(2), latitude: 0, longitude: 0, altitude: 12, horizontalAccuracy: 5, speed: 3),
            RouteLocation(timestamp: t0, latitude: 0, longitude: 0, altitude: 10, horizontalAccuracy: 4, speed: 3),
            RouteLocation(timestamp: t0.addingTimeInterval(1), latitude: 0, longitude: 0, altitude: nil, horizontalAccuracy: 120, speed: nil),
            RouteLocation(timestamp: t0.addingTimeInterval(3), latitude: 0, longitude: 0, altitude: 11, horizontalAccuracy: -1, speed: nil),
            RouteLocation(timestamp: t0.addingTimeInterval(4), latitude: 0, longitude: 0, altitude: nil, horizontalAccuracy: nil, speed: nil),
        ]
        let filtered = RunSeriesMath.filteredRoute(route)
        #expect(filtered.map(\.timestamp) == [t0, t0.addingTimeInterval(2), t0.addingTimeInterval(4)])
        #expect(RunSeriesMath.elevationSeries(from: filtered).map(\.value) == [10, 12])
    }

    // MARK: Vitals

    func night(day: LocalDay, from start: Date, to end: Date, primary: Bool = true) -> SleepNight {
        SleepNight(id: day.isoString, day: day, isPrimary: primary, inBedStart: start, inBedEnd: end, sleepStart: start, sleepEnd: end,
                   segments: [], stageDurations: SleepStageDurations(core: end.timeIntervalSince(start)), interruptions: 0, sources: [])
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func vitalsUseSleepWindow() throws {
        let monday = LocalDay(year: 2026, month: 10, day: 19)
        let nights = [night(day: monday, from: at(18, 23), to: at(19, 7))]
        let hrv = [MetricSample(date: at(18, 21), value: 30), // before bed: ignored
                   MetricSample(date: at(19, 1), value: 60), MetricSample(date: at(19, 5), value: 70),
                   MetricSample(date: at(19, 12), value: 20)] // daytime: ignored
        let vitals = VitalsAssembler(calendar: calendar).dailyVitals(
            days: [monday], nights: nights, heartRateVariability: hrv,
            respiratoryRate: [MetricSample(date: at(19, 3), value: 14)],
            oxygenSaturation: [MetricSample(date: at(19, 2), value: 96), MetricSample(date: at(19, 4), value: 98)],
            wristTemperature: [MetricSample(date: at(19, 7), value: 36.4)],
            restingHeartRate: [monday: 52])
        let day = try #require(vitals.first)
        #expect(vitals.count == 1)
        #expect(day.heartRateVariability == 65)
        #expect(day.respiratoryRate == 14)
        #expect(day.oxygenSaturation == 97)
        #expect(day.wristTemperature == 36.4)
        #expect(day.restingHeartRate == 52)
    }

    @Test func vitalsFallbackWindowWithoutNight() throws {
        let monday = LocalDay(year: 2026, month: 10, day: 19)
        let assembler = VitalsAssembler(calendar: calendar)
        let window = assembler.window(for: monday, night: nil)
        #expect(window.start == at(18, 20))
        #expect(window.end == at(19, 10))
        let vitals = assembler.dailyVitals(days: [monday], nights: [], heartRateVariability: [MetricSample(date: at(19, 4), value: 50)],
                                           respiratoryRate: [], oxygenSaturation: [], wristTemperature: [], restingHeartRate: [:])
        #expect(vitals.first?.heartRateVariability == 50)
        #expect(vitals.first?.recordedMetrics == [.heartRateVariability])
    }

    @Test func vitalsOmitDaysWithoutData() {
        let days = LocalDay.range(from: LocalDay(year: 2026, month: 10, day: 17), through: LocalDay(year: 2026, month: 10, day: 19), calendar: calendar)
        let vitals = VitalsAssembler(calendar: calendar).dailyVitals(
            days: days, nights: [], heartRateVariability: [], respiratoryRate: [], oxygenSaturation: [],
            wristTemperature: [MetricSample(date: at(18, 6), value: 36.2)], restingHeartRate: [LocalDay(year: 2026, month: 10, day: 19): 55])
        #expect(vitals.map(\.day.day) == [18, 19])
        #expect(VitalsAssembler(calendar: calendar).dailyVitals(days: days, nights: [], heartRateVariability: [], respiratoryRate: [],
                                                                oxygenSaturation: [], wristTemperature: [], restingHeartRate: [:]).isEmpty)
    }

    @Test func vitalsIgnoreNaps() {
        let monday = LocalDay(year: 2026, month: 10, day: 19)
        let nap = night(day: monday, from: at(19, 14), to: at(19, 15), primary: false)
        let vitals = VitalsAssembler(calendar: calendar).dailyVitals(
            days: [monday], nights: [nap], heartRateVariability: [MetricSample(date: at(19, 14, 30), value: 80), MetricSample(date: at(19, 3), value: 40)],
            respiratoryRate: [], oxygenSaturation: [], wristTemperature: [], restingHeartRate: [:])
        #expect(vitals.first?.heartRateVariability == 40) // fallback overnight window, not the nap
    }

    @Test func daysOverlappingInterval() {
        let monday = LocalDay(year: 2026, month: 10, day: 19)
        #expect(LocalDay.days(overlapping: monday.interval(in: calendar), calendar: calendar) == [monday])
        let span = LocalDay.interval(from: monday.adding(days: -2, calendar: calendar), through: monday, calendar: calendar)
        #expect(LocalDay.days(overlapping: span, calendar: calendar).count == 3)
    }
}

import Foundation

/// Data situations the mock can simulate (drive the state screens and previews).
/// Select at launch with `-VigilMockScenario <rawValue>`.
enum MockScenario: String, CaseIterable, Codable, Sendable {
    /// ~1 year of plausible history: nightly sleep, vitals, runs Tue/Thu/Sat, lifts Mon/Fri.
    case standard
    /// First launch: Health permission not requested yet.
    case newUser
    /// Permission requested but nothing readable (StateDenied).
    case healthAccessDenied
    /// No sleep recorded last night (StateNoSleep).
    case noSleepLastNight
    /// No runs in the last 7 days (StateNoRuns).
    case noRunsThisWeek
    /// Last night lacks respiratory rate and wrist temperature (StatePartial).
    case partialData
    /// Authorized, but Health is completely empty.
    case empty
}

/// Deterministic in-memory `HealthDataSource` for the simulator, previews and tests.
/// Owner: mock-data agent (Phase 0 provides a compact generator to build on).
///
/// Data is generated from a seeded RNG keyed by calendar day, so the same day always yields the
/// same values and repeated calls agree with each other. Nothing after `referenceDate` exists.
struct MockHealthDataSource: HealthDataSource {
    var scenario: MockScenario
    /// "Now" for the mock. Defaults to the real current time so the simulator always looks fresh.
    var referenceDate: Date
    var calendar: Calendar
    /// How far back data exists.
    var historyDays: Int

    init(scenario: MockScenario = .standard, referenceDate: Date = .now, calendar: Calendar = .current, historyDays: Int = 400) {
        self.scenario = scenario
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.historyDays = historyDays
    }

    static let watch = DataSourceInfo(name: "Apple Watch", bundleIdentifier: "com.apple.health", deviceName: "Apple Watch Series 12")
    static let workoutApp = DataSourceInfo(name: "Workout", bundleIdentifier: "com.apple.workout", deviceName: "Apple Watch Series 12")
    static let hevy = DataSourceInfo(name: "Hevy", bundleIdentifier: "com.hevyapp.hevy", deviceName: nil)

    private var today: LocalDay { LocalDay(referenceDate, calendar: calendar) }
    private var firstDay: LocalDay { today.adding(days: -historyDays, calendar: calendar) }
    private var hasData: Bool { ![.newUser, .healthAccessDenied, .empty].contains(scenario) }

    // MARK: Authorization

    var isHealthDataAvailable: Bool { true }

    func authorizationStatus() async -> HealthAuthorizationStatus {
        scenario == .newUser ? .notDetermined : .requested
    }

    func requestAuthorization() async throws {}

    func characteristics() async throws -> UserCharacteristics {
        guard hasData else { return UserCharacteristics() }
        let birth = DateComponents(year: calendar.component(.year, from: referenceDate) - 21, month: 3, day: 14)
        let mass = try await samples(of: .bodyMass, in: DateInterval(start: referenceDate.addingTimeInterval(-30 * 86_400), end: referenceDate)).last
        return UserCharacteristics(dateOfBirth: birth, biologicalSex: .male, latestBodyMass: mass)
    }

    // MARK: Sleep

    func sleepNights(in interval: DateInterval) async throws -> [SleepNight] {
        days(overlapping: interval).compactMap { night(for: $0) }.filter { interval.contains($0.sleepEnd) }
    }

    // MARK: Metrics

    func samples(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample] {
        switch metric {
        case .heartRate:
            return try await heartRateSamples(in: interval)
        case .vo2Max:
            return days(overlapping: interval).filter { $0.key % 7 == 0 }.map { day in
                let progress = Double(firstDay.days(to: day, calendar: calendar)) / Double(historyDays)
                return MetricSample(date: at(day, hour: 8), value: 45.5 + 2.5 * progress + jitter(day, 11, 0.3), sourceName: Self.watch.deviceName)
            }.filter { interval.contains($0.date) }
        case .bodyMass:
            return days(overlapping: interval).filter { $0.key % 2 == 0 }.map { day in
                let progress = Double(firstDay.days(to: day, calendar: calendar)) / Double(historyDays)
                return MetricSample(date: at(day, hour: 7), value: 80.0 - 1.6 * progress + jitter(day, 12, 0.3), sourceName: "Health")
            }.filter { interval.contains($0.date) }
        default:
            return days(overlapping: interval).compactMap { day in
                vitals(for: day)?[metric].map { MetricSample(date: at(day, hour: 4), value: $0, sourceName: Self.watch.deviceName) }
            }.filter { interval.contains($0.date) }
        }
    }

    func dailyVitals(in interval: DateInterval) async throws -> [DailyVitals] {
        days(overlapping: interval).compactMap { vitals(for: $0) }
    }

    // MARK: Activity

    func dailyActivity(in interval: DateInterval) async throws -> [DailyActivity] {
        guard hasData else { return [] }
        return days(overlapping: interval).map { day in
            var r = rng(day, 3)
            let fraction = day == today ? min(1, max(0, referenceDate.timeIntervalSince(day.startDate(in: calendar)) / 86_400)) : 1
            return DailyActivity(day: day,
                                 steps: Int(Double(r.int(in: 6_000...13_000)) * fraction),
                                 activeEnergyKilocalories: r.double(in: 380...720) * fraction,
                                 basalEnergyKilocalories: 1_750 * fraction,
                                 exerciseMinutes: r.double(in: 15...70) * fraction,
                                 standHours: Int(Double(r.int(in: 8...13)) * fraction),
                                 goals: ActivityGoals(moveKilocalories: 600, exerciseMinutes: 30, standHours: 12))
        }
    }

    // MARK: Workouts

    func workouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout] {
        days(overlapping: interval)
            .flatMap { workouts(on: $0) }
            .filter { interval.contains($0.start) && (kinds?.contains($0.kind) ?? true) }
    }

    func workout(id: UUID) async throws -> Workout? {
        guard let day = Self.day(fromWorkoutID: id) else { return nil }
        return workouts(on: day).first { $0.id == id }
    }

    func runDetails(for workoutID: UUID) async throws -> RunDetails {
        guard let run = try await workout(id: workoutID), run.kind == .run else { throw HealthDataError.notFound }
        let distance = run.distanceMeters ?? 0
        let duration = run.duration
        var r = rng(LocalDay(run.start, calendar: calendar), 21)
        let step: TimeInterval = 5
        let count = Int(duration / step)
        var route: [RouteLocation] = [], hr: [MetricSample] = [], pace: [MetricSample] = []
        var elevation: [MetricSample] = [], cumulative: [MetricSample] = [], cadence: [MetricSample] = []
        let basePace = duration / (distance / 1_000)
        let radius = distance / (2 * .pi) // loop course
        let center = (lat: 52.3676, lon: 4.9041)
        for i in 0...count {
            let t = run.start.addingTimeInterval(Double(i) * step)
            let progress = Double(i) / Double(max(count, 1))
            let covered = distance * progress
            let angle = covered / radius
            let lat = center.lat + (radius * sin(angle)) / 111_320
            let lon = center.lon + (radius * (1 - cos(angle))) / (111_320 * cos(center.lat * .pi / 180))
            let alt = 8 + 12 * sin(angle * 2) + r.double(in: -0.4...0.4)
            route.append(RouteLocation(timestamp: t, latitude: lat, longitude: lon, altitude: alt, horizontalAccuracy: 4, speed: 1_000 / basePace))
            hr.append(MetricSample(date: t, value: min(185, 112 + 45 * min(1, progress * 6) + 10 * progress + r.double(in: -3...3))))
            pace.append(MetricSample(date: t, value: basePace + 12 * sin(progress * 9) + r.double(in: -6...6)))
            elevation.append(MetricSample(date: t, value: alt))
            cumulative.append(MetricSample(date: t, value: covered))
            cadence.append(MetricSample(date: t, value: 172 + r.double(in: -4...4)))
        }
        return RunDetails(workoutID: workoutID, route: route, heartRate: hr, pace: pace, elevation: elevation,
                          cumulativeDistance: cumulative, cadence: cadence,
                          form: RunningFormSummary(cadence: 172, strideLength: 1.10, groundContactTime: 248, verticalOscillation: 8.6, power: 268))
    }

    func heartRateSamples(in interval: DateInterval) async throws -> [MetricSample] {
        guard hasData else { return [] }
        let end = min(interval.end, referenceDate)
        guard end > interval.start else { return [] }
        let dayWorkouts = days(overlapping: interval).flatMap { workouts(on: $0) }
        let step: TimeInterval = interval.duration <= 6 * 3600 ? 10 : 300
        var samples: [MetricSample] = []
        var t = interval.start
        var r = rng(LocalDay(interval.start, calendar: calendar), 31)
        while t < end {
            let value: Double
            if let w = dayWorkouts.first(where: { $0.interval.contains(t) }) {
                let p = t.timeIntervalSince(w.start) / max(w.duration, 1)
                value = w.kind == .run
                    ? 112 + 45 * min(1, p * 6) + 10 * p + r.double(in: -3...3)
                    : 110 + (Int(t.timeIntervalSince(w.start) / 60) % 4 < 1 ? 30 : 8) + r.double(in: -5...5)
            } else {
                value = 62 + r.double(in: -6...10)
            }
            samples.append(MetricSample(date: t, value: value, sourceName: Self.watch.deviceName))
            t.addTimeInterval(step)
        }
        return samples
    }

    func updates() -> AsyncStream<HealthDataUpdate> {
        AsyncStream { continuation in continuation.finish() }
    }

    // MARK: - Generators

    private func days(overlapping interval: DateInterval) -> [LocalDay] {
        let start = max(LocalDay(interval.start, calendar: calendar), firstDay)
        let end = min(LocalDay(interval.end.addingTimeInterval(-1), calendar: calendar), today)
        return LocalDay.range(from: start, through: end, calendar: calendar)
    }

    private func at(_ day: LocalDay, hour: Int, minute: Int = 0) -> Date {
        calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day.startDate(in: calendar)) ?? day.startDate(in: calendar)
    }

    private func rng(_ day: LocalDay, _ salt: UInt64) -> SeededGenerator {
        SeededGenerator(seed: UInt64(day.key) &* 1_000_003 &+ salt)
    }

    private func jitter(_ day: LocalDay, _ salt: UInt64, _ amplitude: Double) -> Double {
        var generator = rng(day, salt)
        return generator.double(in: -amplitude...amplitude)
    }

    func vitals(for day: LocalDay) -> DailyVitals? {
        guard hasData, day <= today, day >= firstDay else { return nil }
        if scenario == .noSleepLastNight && day == today { return DailyVitals(day: day, heartRateVariability: 58, restingHeartRate: 54) }
        var r = rng(day, 1)
        var v = DailyVitals(day: day,
                            heartRateVariability: (61 + r.double(in: -9...9)).rounded(),
                            restingHeartRate: (54 + r.double(in: -2.5...2.5)).rounded(),
                            respiratoryRate: 14.6 + r.double(in: -0.3...0.3),
                            wristTemperature: 36.40 + r.double(in: -0.15...0.2),
                            oxygenSaturation: (97 + r.double(in: -1.4...1.4)).rounded())
        if scenario == .partialData && day == today {
            v.respiratoryRate = nil
            v.wristTemperature = nil
        }
        return v
    }

    func night(for day: LocalDay) -> SleepNight? {
        guard hasData, day <= today, day >= firstDay else { return nil }
        if scenario == .noSleepLastNight && day == today { return nil }
        var r = rng(day, 2)
        let previous = day.adding(days: -1, calendar: calendar)
        let inBedStart = at(previous, hour: 22, minute: r.int(in: 30...75))
        let sleepStart = inBedStart.addingTimeInterval(Double(r.int(in: 4...16)) * 60)
        let asleepTarget = Double(r.int(in: 390...490)) * 60
        // Build ~90-minute cycles: core → deep → core → REM, with deep shrinking and REM growing.
        var segments: [SleepSegment] = []
        var t = sleepStart
        let end = sleepStart.addingTimeInterval(asleepTarget * 1.04)
        var cycle = 0
        var interruptions = 0
        while t < end {
            let deep = max(5, 45 - Double(cycle) * 11) * 60
            let rem = min(40, 12 + Double(cycle) * 7) * 60
            let pattern: [(SleepStage, TimeInterval)] = [(.core, 22 * 60), (.deep, deep), (.core, 18 * 60), (.rem, rem)]
            for (stage, length) in pattern where t < end {
                let segmentEnd = min(end, t.addingTimeInterval(length * r.double(in: 0.85...1.15)))
                segments.append(SleepSegment(stage: stage, start: t, end: segmentEnd, source: Self.watch))
                t = segmentEnd
            }
            if t < end && r.double(in: 0...1) < 0.7 {
                let awakeEnd = t.addingTimeInterval(Double(r.int(in: 2...9)) * 60)
                segments.append(SleepSegment(stage: .awake, start: t, end: awakeEnd, source: Self.watch))
                t = awakeEnd
                interruptions += 1
            }
            cycle += 1
        }
        var durations = SleepStageDurations()
        for s in segments {
            switch s.stage {
            case .awake: durations.awake += s.duration
            case .rem: durations.rem += s.duration
            case .core: durations.core += s.duration
            case .deep: durations.deep += s.duration
            case .asleepUnspecified: durations.unspecified += s.duration
            case .inBed: break
            }
        }
        let sleepEnd = segments.last?.end ?? end
        return SleepNight(id: "\(day.isoString)-primary", day: day, isPrimary: true,
                          inBedStart: inBedStart, inBedEnd: sleepEnd.addingTimeInterval(Double(r.int(in: 2...12)) * 60),
                          sleepStart: sleepStart, sleepEnd: sleepEnd, segments: segments, stageDurations: durations,
                          interruptions: interruptions, sources: [Self.watch])
    }

    func workouts(on day: LocalDay) -> [Workout] {
        guard hasData, day <= today, day >= firstDay else { return [] }
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar)) // 1 = Sunday
        var result: [Workout] = []
        var r = rng(day, 4)
        let isRunDay = [3, 5, 7].contains(weekday) || (weekday == 2 && day == today)
        let suppressRun = scenario == .noRunsThisWeek && day.days(to: today, calendar: calendar) < 7
        if isRunDay && !suppressRun {
            let isLong = weekday == 7
            let distance = isLong ? r.double(in: 10_000...13_000) : r.double(in: 5_000...8_200)
            let pace = r.double(in: 300...335) // s/km
            let start = at(day, hour: 7, minute: 12)
            let duration = distance / 1_000 * pace
            let names = ["Outdoor Run", "Easy Run", "Tempo Run", "Intervals"]
            result.append(Workout(id: Self.workoutID(day: day, slot: 1), kind: .run, activityName: "Outdoor Run",
                                  title: isLong ? "Long Run" : names[r.int(in: 0...3)],
                                  start: start, end: start.addingTimeInterval(duration), duration: duration,
                                  activeEnergyKilocalories: distance / 1_000 * 70, totalEnergyKilocalories: distance / 1_000 * 82,
                                  averageHeartRate: r.double(in: 142...160), maxHeartRate: r.double(in: 168...182),
                                  distanceMeters: distance, elevationGainMeters: r.double(in: 20...70), elevationLossMeters: r.double(in: 20...65),
                                  source: Self.workoutApp, heartRateSource: Self.watch, isIndoor: false, hasRoute: true))
        }
        if [2, 6].contains(weekday) {
            let start = at(day, hour: 18, minute: 30)
            let duration = Double(r.int(in: 50...62)) * 60
            let titles = ["Upper Body", "Lower Body", "Full Body"]
            result.append(Workout(id: Self.workoutID(day: day, slot: 2), kind: .strength, activityName: "Traditional Strength Training",
                                  title: titles[r.int(in: 0...2)], start: start, end: start.addingTimeInterval(duration), duration: duration,
                                  activeEnergyKilocalories: duration / 60 * 7.1, totalEnergyKilocalories: duration / 60 * 8.6,
                                  averageHeartRate: r.double(in: 122...130), maxHeartRate: r.double(in: 155...168),
                                  distanceMeters: nil, elevationGainMeters: nil, elevationLossMeters: nil,
                                  source: Self.hevy, heartRateSource: Self.watch, isIndoor: true, hasRoute: false))
        }
        return result.filter { $0.end <= referenceDate }
    }

    /// Stable UUIDs encoding the day so `workout(id:)` can regenerate without a lookup table.
    static func workoutID(day: LocalDay, slot: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", day.key * 10 + slot))!
    }

    static func day(fromWorkoutID id: UUID) -> LocalDay? {
        guard let raw = Int(id.uuidString.suffix(12)) else { return nil }
        let key = raw / 10
        return LocalDay(year: key / 10_000, month: (key / 100) % 100, day: key % 100)
    }
}

/// SplitMix64 — tiny deterministic RNG for mock data.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
}

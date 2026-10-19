import Foundation

extension DefaultScoreEngine {
    /// Tunable constants of zones, strain and training load.
    enum Strain {
        /// Strain = 100 × (1 − e^(−load / 120)): load 36 → 26, 80 → 49, 150 → 71, 280 → 90.
        static let saturationLoad = 120.0
        /// Banister TRIMP coefficients: TRIMP/min = HRr × a × e^(b × HRr).
        static let maleCoefficients = (a: 0.64, b: 1.92)
        static let femaleCoefficients = (a: 0.86, b: 1.67)
        /// Mean of both curves when sex is unknown / other.
        static let neutralCoefficients = (a: 0.75, b: 1.795)
        /// Resting HR assumed when none is recorded, bpm.
        static let defaultRestingHeartRate = 60.0
        /// Each HR sample holds until the next one, capped (same rule as zone time).
        static let maximumSampleGap: TimeInterval = 60
        /// Below this much HR coverage, the workout's average HR (or an assumed intensity) is used.
        static let minimumHeartRateCoverage: TimeInterval = 60
        /// Assumed heart-rate reserve when a workout has no HR at all.
        static let assumedReserve: [WorkoutKind: Double] = [.run: 0.6, .strength: 0.45, .other: 0.4]
        /// Everyday movement: TRIMP-equivalent per non-workout active kcal (≈ walking at 30 % HRR, ~4.5 kcal/min).
        static let everydayLoadPerKilocalorie = 0.07
        /// kcal assumed per TRIMP unit for workouts that don't report active energy.
        static let kilocaloriesPerLoadUnit = 6.0
        /// EWMA spans (days) for acute and chronic load.
        static let acuteSpan = 7.0
        static let chronicSpan = 28.0
    }

    // MARK: Zones

    /// Five heart-rate zones.
    ///
    /// Max HR = 208 − 0.7 × age (Tanaka; age 35 when unknown), raised to the highest observed workout max
    /// when estimating, or the user's manual max. Automatic zones start at 50/60/70/80/90 % of max HR;
    /// each zone ends 1 bpm below the next, Z5 ends at max HR. Custom zones use the user's four
    /// upper bounds (must be strictly ascending and positive; otherwise automatic zones are used).
    func heartRateZones(profile: UserProfile, settings: HeartRateZoneSettings, observedMaxHeartRate: Double?, on date: Date) -> HeartRateZones {
        let age = profile.age(on: date, calendar: calendar) ?? 35
        let estimated = Int((208 - 0.7 * Double(age)).rounded())
        var maxHR = profile.estimatesMaxHeartRate ? estimated : (profile.manualMaxHeartRate ?? estimated)
        var source: HeartRateZoneSource = profile.estimatesMaxHeartRate || profile.manualMaxHeartRate == nil ? .estimated : .manualMaxHeartRate
        if profile.estimatesMaxHeartRate, let observedMaxHeartRate, observedMaxHeartRate.isFinite,
           observedMaxHeartRate < 250, Int(observedMaxHeartRate) > maxHR {
            maxHR = Int(observedMaxHeartRate)
        }
        var lowerBounds = [0.5, 0.6, 0.7, 0.8, 0.9].map { Int((Double(maxHR) * $0).rounded()) }
        let custom = settings.customUpperBounds
        if settings.usesCustomZones, custom.count == 4, custom[0] > 0,
           zip(custom, custom.dropFirst()).allSatisfy({ $0 < $1 }) {
            lowerBounds = [min(lowerBounds[0], custom[0])] + custom.map { $0 + 1 }
            maxHR = max(maxHR, lowerBounds[4])
            source = .custom
        }
        let zones = (0..<5).map { i in
            HeartRateZone(number: i + 1, name: HeartRateZone.names[i], lowerBound: lowerBounds[i],
                          upperBound: i < 4 ? lowerBounds[i + 1] - 1 : maxHR)
        }
        return HeartRateZones(maxHeartRate: maxHR, source: source, zones: zones)
    }

    /// Time in zone: samples inside `interval`, sorted; each holds until the next sample (or the
    /// interval end), capped at 60 s. Samples below Z1 are not counted.
    func zoneDurations(heartRate: [MetricSample], zones: HeartRateZones, interval: DateInterval) -> ZoneDurations {
        var seconds = Array(repeating: 0.0, count: 5)
        Self.forEachHeldSample(heartRate, in: interval) { bpm, duration in
            if let zone = zones.zone(for: bpm) { seconds[zone - 1] += duration }
        }
        return ZoneDurations(seconds: seconds)
    }

    /// Calls `body(value, heldSeconds)` for every finite sample in `interval` (sorted by date).
    static func forEachHeldSample(_ samples: [MetricSample], in interval: DateInterval, _ body: (Double, TimeInterval) -> Void) {
        let inside = samples.filter { interval.contains($0.date) && $0.value.isFinite && $0.value > 0 }.sorted { $0.date < $1.date }
        for (i, sample) in inside.enumerated() {
            let next = i + 1 < inside.count ? inside[i + 1].date : interval.end
            body(sample.value, min(Strain.maximumSampleGap, max(0, next.timeIntervalSince(sample.date))))
        }
    }

    // MARK: Strain

    /// Banister TRIMP per minute at heart-rate reserve `reserve` (0…1).
    static func trimpPerMinute(reserve: Double, sex: BiologicalSex?) -> Double {
        let c = switch sex {
        case .male: Strain.maleCoefficients
        case .female: Strain.femaleCoefficients
        case .other, nil: Strain.neutralCoefficients
        }
        let hrr = EngineMath.clamp(reserve, 0...1)
        return hrr * c.a * exp(c.b * hrr)
    }

    /// Maps a training load (TRIMP) to the 0–100 strain scale: 100 × (1 − e^(−load / 120)).
    static func strain(forLoad load: Double) -> Int {
        clampScore(100 * (1 - exp(-max(0, load) / Strain.saturationLoad)))
    }

    /// Workout strain from heart-rate-reserve TRIMP (Banister 1991). Runs and lifts use the same method.
    ///
    /// HRr = (HR − resting) / (max − resting), clamped 0…1, with resting = the day's resting HR (60 if
    /// unknown) and max = the zones' max HR. TRIMP = Σ minutes × HRr × a·e^(b·HRr) over HR samples
    /// (each held ≤ 60 s), with a = 0.64, b = 1.92 for men; 0.86, 1.67 for women; 0.75, 1.795 otherwise.
    /// With < 60 s of HR, the workout's average HR × duration is used; without any HR an assumed
    /// HRr (run 0.6, strength 0.45, other 0.4). Strain = 100 × (1 − e^(−TRIMP / 120)).
    func workoutStrain(_ input: WorkoutStrainInput) -> WorkoutStrain {
        let workout = input.workout
        let durations = zoneDurations(heartRate: input.heartRate, zones: input.zones, interval: workout.interval)
        let rest = input.restingHeartRate.flatMap { $0.isFinite && $0 > 25 ? $0 : nil } ?? Strain.defaultRestingHeartRate
        let maxHR = max(Double(input.zones.maxHeartRate), rest + 40)
        let reserve: (Double) -> Double = { ($0 - rest) / (maxHR - rest) }

        var load = 0.0
        var covered: TimeInterval = 0
        Self.forEachHeldSample(input.heartRate, in: workout.interval) { bpm, seconds in
            load += seconds / 60 * Self.trimpPerMinute(reserve: reserve(bpm), sex: input.sex)
            covered += seconds
        }
        if covered < Strain.minimumHeartRateCoverage {
            let minutes = max(0, workout.duration) / 60
            if let average = workout.averageHeartRate, average.isFinite, average > 0 {
                load = minutes * Self.trimpPerMinute(reserve: reserve(average), sex: input.sex)
            } else {
                load = minutes * Self.trimpPerMinute(reserve: Strain.assumedReserve[workout.kind] ?? 0.4, sex: input.sex)
            }
        }
        let value = Self.strain(forLoad: load)
        return WorkoutStrain(workoutID: workout.id, value: value, level: StrainLevel(strain: value),
                             trainingLoad: load, zoneDurations: durations,
                             activeEnergyKilocalories: workout.activeEnergyKilocalories)
    }

    /// Day strain.
    ///
    /// Everyday load = 0.07 × non-workout active kcal, where non-workout kcal = the day's active energy
    /// − Σ workout active energy (workouts without energy count 6 kcal per TRIMP unit).
    /// Day load = Σ workout TRIMP + everyday load; day strain = 100 × (1 − e^(−load / 120)), so it is
    /// less than the sum of the parts. `everydayMovement` is the strain of the everyday load alone.
    func dailyStrain(day: LocalDay, workouts: [WorkoutStrain], activity: DailyActivity?) -> DailyStrain {
        let workoutLoad = workouts.reduce(0) { $0 + $1.trainingLoad }
        let workoutKilocalories = workouts.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? $1.trainingLoad * Strain.kilocaloriesPerLoadUnit) }
        let everydayKilocalories = max(0, (activity?.activeEnergyKilocalories ?? 0) - workoutKilocalories)
        let everydayLoad = everydayKilocalories * Strain.everydayLoadPerKilocalorie
        let load = workoutLoad + everydayLoad
        let value = Self.strain(forLoad: load)
        return DailyStrain(day: day, value: value, level: StrainLevel(strain: value), workouts: workouts,
                           everydayMovement: Self.strain(forLoad: everydayLoad),
                           zoneDurations: workouts.reduce(ZoneDurations()) { $0 + $1.zoneDurations },
                           trainingLoad: load)
    }

    // MARK: Training load

    /// Acute vs. chronic training load (exponentially weighted moving averages).
    ///
    /// For each day: acute ← acute + α₇ (load − acute) with α₇ = 2 / (7 + 1);
    /// chronic ← chronic + α₂₈ (load − chronic) with α₂₈ = 2 / (28 + 1). Missing days are 0 load.
    /// The series starts at the earliest day in `dailyLoads` (at most `historyDays` + 84 days back) and
    /// both averages are seeded with the mean load of its first 28 days, so a short history doesn't read
    /// as a sudden spike. Ratio = acute ÷ chronic (nil when chronic is 0).
    /// Bands: < 0.8 detraining, 0.8–1.3 productive, 1.3–1.5 caution, > 1.5 high.
    func trainingLoad(dailyLoads: [LocalDay: Double], asOf day: LocalDay, historyDays: Int) -> TrainingLoad {
        let historyDays = max(1, historyDays)
        let earliestAllowed = day.adding(days: -(historyDays + 84), calendar: calendar)
        let earliestKey = dailyLoads.keys.filter { $0 <= day }.min() ?? day
        let start = max(earliestAllowed, min(earliestKey, day.adding(days: -(historyDays - 1), calendar: calendar)))
        let days = LocalDay.range(from: start, through: day, calendar: calendar)
        let loads = days.map { max(0, dailyLoads[$0] ?? 0) }

        let seed = EngineMath.mean(Array(loads.prefix(Int(Strain.chronicSpan)))) ?? 0
        var acute = seed, chronic = seed
        let acuteAlpha = 2 / (Strain.acuteSpan + 1), chronicAlpha = 2 / (Strain.chronicSpan + 1)
        var points: [TrainingLoadPoint] = []
        points.reserveCapacity(days.count)
        for (d, load) in zip(days, loads) {
            acute += acuteAlpha * (load - acute)
            chronic += chronicAlpha * (load - chronic)
            points.append(TrainingLoadPoint(day: d, acute: acute, chronic: chronic))
        }
        let ratio: Double? = chronic > 1e-9 ? acute / chronic : nil
        return TrainingLoad(day: day, acute: acute, chronic: chronic, ratio: ratio,
                            risk: TrainingLoadRisk(ratio: ratio ?? 0), history: Array(points.suffix(historyDays)))
    }
}

import CoreLocation
import Foundation
import HealthKit
import Synchronization
import UIKit

/// HealthKit-backed `HealthDataSource`. Owner: HealthKit agent. Read-only: nothing is ever written to Health.
///
/// Behaviour notes:
///  - **Authorization.** HealthKit never reveals whether *read* access was denied.
///    `authorizationStatus()` uses `statusForAuthorizationRequest(toShare:read:)`: `.unnecessary` → `.requested`
///    (the sheet was shown for every type Vigil reads), `.shouldRequest` / `.unknown` → `.notDetermined`.
///    If a future version adds read types, the status falls back to `.notDetermined` so the sheet is shown again
///    for the new types. `VigilRepository.healthAccessState()` turns `.requested` + "no data anywhere" into
///    `.likelyDenied`. Denied types simply return no samples, so every method returns empty / nil.
///  - **Errors.** "No data" and authorization errors become empty results. A locked device
///    (`errorDatabaseInaccessible`) throws `.protectedDataUnavailable`; unavailable Health throws or returns empty
///    as documented per method; everything else is `.underlying(description)`. Cancellation is rethrown.
///  - **Units.** Everything is converted to the canonical units of `HealthMetric` / `RunDetails`.
///  - **Concurrency.** A `Sendable` struct: all methods are nonisolated `async`, so they run on the global
///    executor (never the main actor). Independent queries run concurrently with `async let` / task groups.
struct LiveHealthDataSource: HealthDataSource {
    /// Shared store; `HKHealthStore` is thread-safe and Sendable.
    let store: HKHealthStore
    /// Calendar used for day bucketing (`LocalDay`) — the user's current calendar and time zone.
    let calendar: Calendar
    /// Route / heart-rate lookups per workout (workouts are immutable, so entries never expire).
    let derivedCache = WorkoutDerivedCache()

    /// Sleep samples are fetched with this much context before / after the requested interval so sessions that
    /// straddle the interval edges are reconstructed completely before filtering by wake time.
    static let sleepLookback: TimeInterval = 36 * 3600
    static let sleepLookahead: TimeInterval = 18 * 3600
    /// `samples(of: .heartRate, …)` returns hourly averages instead of raw samples beyond this span
    /// (a week of raw HR is tens of thousands of samples).
    static let rawHeartRateMaximumSpan: TimeInterval = 2 * 86_400
    /// Bucket size for the cumulative-distance series of a run (deduplicated by HealthKit statistics).
    static let distanceBucketSeconds = 5
    /// A workout younger than this may still receive its route / heart rate, so incomplete lookups aren't cached.
    static let derivedSettleInterval: TimeInterval = 24 * 3600

    init(store: HKHealthStore = HKHealthStore(), calendar: Calendar = .autoupdatingCurrent) {
        self.store = store
        self.calendar = calendar
    }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    /// Upper bound for `authorizationStatus()`. On device healthd answers in milliseconds; in unsigned simulator
    /// builds it can take minutes, which must not block launch / onboarding.
    static let authorizationStatusTimeout: Duration = .seconds(10)

    func authorizationStatus() async -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else { return .unavailable }
        let store = store
        // Unstructured race: the HealthKit call can't be cancelled, so a task group would still wait for it.
        return await withCheckedContinuation { continuation in
            let resume = ResumeOnce(continuation)
            Task {
                let status: HealthAuthorizationStatus
                do {
                    switch try await store.statusForAuthorizationRequest(toShare: [], read: HealthKitTypes.readTypes) {
                    case .unnecessary: status = .requested
                    case .shouldRequest, .unknown: status = .notDetermined
                    @unknown default: status = .notDetermined
                    }
                } catch {
                    status = .notDetermined
                }
                resume(status)
            }
            Task {
                try? await Task.sleep(for: Self.authorizationStatusTimeout)
                resume(.notDetermined)
            }
        }
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthDataError.healthDataUnavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: HealthKitTypes.readTypes)
        } catch {
            throw HealthDataError.mapping(error) ?? .underlying(error.localizedDescription)
        }
    }

    // MARK: - Characteristics

    func characteristics() async throws -> UserCharacteristics {
        guard isHealthDataAvailable else { return UserCharacteristics() }
        let dateOfBirth = try? store.dateOfBirthComponents()
        let sex = (try? store.biologicalSex()).flatMap { BiologicalSex($0.biologicalSex) }
        let mass = try await guarded(empty: [HKQuantitySample]()) {
            try await quantitySamples(HealthKitTypes.bodyMass, in: DateInterval(start: .distantPast, end: .distantFuture),
                                      limit: 1, newestFirst: true)
        }.first.flatMap { metricSample($0, metric: .bodyMass) }
        return UserCharacteristics(dateOfBirth: dateOfBirth, biologicalSex: sex, latestBodyMass: mass)
    }

    // MARK: - Sleep

    func sleepNights(in interval: DateInterval) async throws -> [SleepNight] {
        try await guarded(empty: []) {
            let fetch = DateInterval(start: interval.start.addingTimeInterval(-Self.sleepLookback),
                                     end: max(interval.start, interval.end).addingTimeInterval(Self.sleepLookahead))
            let raw = try await rawSleepSamples(in: fetch)
            return SleepNightBuilder(calendar: calendar).nights(from: raw, wakingIn: interval)
        }
    }

    /// Sleep-analysis samples overlapping `interval`, flattened with their source priority.
    private func rawSleepSamples(in interval: DateInterval) async throws -> [RawSleepSample] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HealthKitTypes.sleepAnalysis, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).compactMap { sample in
            guard let stage = SleepStage(sleepAnalysisValue: sample.value) else { return nil }
            let revision = sample.sourceRevision
            let source = DataSourceInfo(sourceRevision: revision, device: sample.device)
            let isWatch = SampleSourceClassifier.isAppleWatch(productType: revision.productType, deviceModel: sample.device?.model)
            let isUserEntered = (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) ?? false
            return RawSleepSample(stage: stage, start: sample.startDate, end: sample.endDate, source: source,
                                  priority: SleepSourcePriority.priority(isAppleWatch: isWatch, isAppleBundle: source.isApple,
                                                                         isUserEntered: isUserEntered))
        }
    }

    // MARK: - Quantity metrics

    func samples(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample] {
        try await guarded(empty: []) {
            if metric == .heartRate, interval.duration > Self.rawHeartRateMaximumSpan {
                return try await hourlyAverages(of: metric, in: interval)
            }
            let raw = try await quantitySamples(metric.quantityType, in: interval,
                                                options: metric.datesSampleByEnd ? .strictEndDate : .strictStartDate)
            return raw.compactMap { metricSample($0, metric: metric) }.sorted { $0.date < $1.date }
        }
    }

    func dailyVitals(in interval: DateInterval) async throws -> [DailyVitals] {
        let nights = try await sleepNights(in: interval)
        return try await dailyVitals(in: interval, nights: nights)
    }

    func dailyVitals(in interval: DateInterval, nights: [SleepNight]) async throws -> [DailyVitals] {
        try await guarded(empty: []) {
            // Overnight samples for the first day start the evening before.
            let overnight = DateInterval(start: interval.start.addingTimeInterval(-Self.sleepLookback), end: interval.end)
            async let hrv = samples(of: .heartRateVariability, in: overnight)
            async let respiratory = samples(of: .respiratoryRate, in: overnight)
            async let oxygen = samples(of: .oxygenSaturation, in: overnight)
            async let temperature = samples(of: .wristTemperature, in: interval)
            async let resting = dailyValues(HealthKitTypes.restingHeartRate, unit: RunningFormUnits.bpm,
                                            options: .discreteAverage, in: interval)
            let assembler = VitalsAssembler(calendar: calendar)
            return try await assembler.dailyVitals(days: LocalDay.days(overlapping: interval, calendar: calendar),
                                                   nights: nights, heartRateVariability: hrv, respiratoryRate: respiratory,
                                                   oxygenSaturation: oxygen, wristTemperature: temperature,
                                                   restingHeartRate: resting)
        }
    }

    // MARK: - Activity

    func dailyActivity(in interval: DateInterval) async throws -> [DailyActivity] {
        try await guarded(empty: []) {
            async let steps = dailyValues(HealthKitTypes.stepCount, unit: RunningFormUnits.count, options: .cumulativeSum, in: interval)
            async let active = dailyValues(HealthKitTypes.activeEnergy, unit: RunningFormUnits.kilocalories, options: .cumulativeSum, in: interval)
            async let basal = dailyValues(HealthKitTypes.basalEnergy, unit: RunningFormUnits.kilocalories, options: .cumulativeSum, in: interval)
            async let exercise = dailyValues(HealthKitTypes.exerciseTime, unit: RunningFormUnits.minutes, options: .cumulativeSum, in: interval)
            async let summaries = activitySummaries(in: interval)
            let (stepsByDay, activeByDay, basalByDay, exerciseByDay, summaryByDay) = try await (steps, active, basal, exercise, summaries)

            let wanted = Set(LocalDay.days(overlapping: interval, calendar: calendar))
            let days = Set(stepsByDay.keys).union(activeByDay.keys).union(exerciseByDay.keys).union(summaryByDay.keys)
                .intersection(wanted).sorted()
            return days.map { day in
                let summary = summaryByDay[day]
                return DailyActivity(day: day,
                                     steps: Int((stepsByDay[day] ?? 0).rounded()),
                                     activeEnergyKilocalories: activeByDay[day] ?? summary?.activeEnergyKilocalories ?? 0,
                                     basalEnergyKilocalories: basalByDay[day],
                                     exerciseMinutes: exerciseByDay[day] ?? summary?.exerciseMinutes ?? 0,
                                     standHours: summary?.standHours ?? 0,
                                     goals: summary?.goals)
            }
        }
    }

    /// Values read from an `HKActivitySummary`.
    private struct ActivitySummaryValues: Sendable {
        var activeEnergyKilocalories: Double
        var exerciseMinutes: Double
        var standHours: Int
        var goals: ActivityGoals?
    }

    private func activitySummaries(in interval: DateInterval) async throws -> [LocalDay: ActivitySummaryValues] {
        try await guarded(empty: [:]) {
            func components(_ date: Date) -> DateComponents {
                var c = calendar.dateComponents([.era, .year, .month, .day], from: date)
                c.calendar = calendar
                return c
            }
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components(interval.start),
                                              end: components(max(interval.start, interval.end.addingTimeInterval(-1))))
            let summaries = try await HKActivitySummaryQueryDescriptor(predicate: predicate).result(for: store)
            var result: [LocalDay: ActivitySummaryValues] = [:]
            for summary in summaries {
                let c = summary.dateComponents(for: calendar)
                guard let year = c.year, let month = c.month, let day = c.day else { continue }
                let moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                let exerciseGoal = summary.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 30
                let standGoal = summary.standHoursGoal.map { Int($0.doubleValue(for: .count()).rounded()) } ?? 12
                result[LocalDay(year: year, month: month, day: day)] = ActivitySummaryValues(
                    activeEnergyKilocalories: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    standHours: Int(summary.appleStandHours.doubleValue(for: .count()).rounded()),
                    goals: moveGoal > 0 ? ActivityGoals(moveKilocalories: moveGoal, exerciseMinutes: exerciseGoal, standHours: standGoal) : nil)
            }
            return result
        }
    }

    // MARK: - Workouts

    func workouts(in interval: DateInterval, kinds: Set<WorkoutKind>?) async throws -> [Workout] {
        try await guarded(empty: []) {
            if let kinds, kinds.isEmpty { return [] }
            var predicate: NSPredicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
            // Narrow the query by activity type unless `.other` ("everything else") is requested.
            if let kinds, !kinds.contains(.other) {
                let types = kinds.compactMap(\.activityTypes).flatMap { $0 }
                let byType = NSCompoundPredicate(orPredicateWithSubpredicates: types.map { HKQuery.predicateForWorkouts(with: $0) })
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, byType])
            }
            let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
            let workouts = try await descriptor.result(for: store).filter { workout in
                workout.startDate >= interval.start && workout.startDate < interval.end
                    && (kinds?.contains(WorkoutKind(activityType: workout.workoutActivityType)) ?? true)
            }
            return try await makeWorkouts(workouts)
        }
    }

    func workout(id: UUID) async throws -> Workout? {
        try await guarded(empty: nil) {
            guard let workout = try await hkWorkout(id: id) else { return nil }
            return try await makeWorkout(workout)
        }
    }

    func heartRateSamples(in interval: DateInterval) async throws -> [MetricSample] {
        try await guarded(empty: []) {
            try await seriesSamples(HealthKitTypes.heartRate, unit: RunningFormUnits.bpm, in: interval)
        }
    }

    private func hkWorkout(id: UUID) async throws -> HKWorkout? {
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: id))],
                                                 sortDescriptors: [], limit: 1)
        return try await descriptor.result(for: store).first
    }

    /// Maps workouts concurrently (each may need a route-existence or HR-statistics query), preserving order.
    private func makeWorkouts(_ input: [HKWorkout]) async throws -> [Workout] {
        // Never return the same HKWorkout twice.
        var seen = Set<UUID>()
        let workouts = input.filter { seen.insert($0.uuid).inserted }
        return try await withThrowingTaskGroup(of: (Int, Workout).self) { group in
            for (index, workout) in workouts.enumerated() {
                group.addTask { (index, try await makeWorkout(workout)) }
            }
            var result = [Workout?](repeating: nil, count: workouts.count)
            for try await (index, workout) in group { result[index] = workout }
            return result.compactMap { $0 }
        }
    }

    private func makeWorkout(_ workout: HKWorkout) async throws -> Workout {
        let activityType = workout.workoutActivityType
        let kind = WorkoutKind(activityType: activityType)
        let metadata = workout.metadata
        let isIndoor = (metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? (kind == .strength)
        let source = DataSourceInfo(sourceRevision: workout.sourceRevision, device: workout.device)
        let interval = DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))

        func sum(_ type: HKQuantityType, _ unit: HKUnit) -> Double? {
            workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
        }
        let active = sum(HealthKitTypes.activeEnergy, .kilocalorie())
        let basal = sum(HealthKitTypes.basalEnergy, .kilocalorie())
        let distance = sum(HealthKitTypes.distanceWalkingRunning, .meter())
        let workoutHeartRate = workout.statistics(for: HealthKitTypes.heartRate)
        var averageHeartRate = workoutHeartRate?.averageQuantity()?.doubleValue(for: RunningFormUnits.bpm)
        var maxHeartRate = workoutHeartRate?.maximumQuantity()?.doubleValue(for: RunningFormUnits.bpm)
        var heartRateSource: DataSourceInfo?

        // Third-party workouts (Hevy, Strong…) usually carry no HR statistics; compute them from the HR the
        // watch recorded during the workout interval. Both lookups are cached per workout.
        let checksRoute = kind == .run && !isIndoor
        var hasRoute = false
        if let cached = await derivedCache.value(for: workout.uuid) {
            hasRoute = cached.hasRoute
            averageHeartRate = cached.averageHeartRate
            maxHeartRate = cached.maxHeartRate
            heartRateSource = cached.heartRateSource
        } else {
            let needsHeartRateFallback = averageHeartRate == nil
            async let fallback: HKStatistics? = needsHeartRateFallback ? heartRateStatistics(in: interval) : nil
            async let routeFlag = checksRoute ? routeExists(for: workout) : false
            if let statistics = try await fallback {
                averageHeartRate = statistics.averageQuantity()?.doubleValue(for: RunningFormUnits.bpm)
                maxHeartRate = statistics.maximumQuantity()?.doubleValue(for: RunningFormUnits.bpm)
                if let hrSource = statistics.sources?.first(where: { $0.bundleIdentifier != source.bundleIdentifier }) {
                    heartRateSource = DataSourceInfo(name: hrSource.name, bundleIdentifier: hrSource.bundleIdentifier)
                }
            }
            hasRoute = try await routeFlag
            // A just-finished workout may still be waiting for its route / watch heart rate to sync: don't pin
            // an incomplete answer.
            let settled = workout.endDate.addingTimeInterval(Self.derivedSettleInterval) < .now
                || ((!checksRoute || hasRoute) && averageHeartRate != nil)
            if settled {
                await derivedCache.store(WorkoutDerived(hasRoute: hasRoute, averageHeartRate: averageHeartRate,
                                                        maxHeartRate: maxHeartRate, heartRateSource: heartRateSource),
                                         for: workout.uuid)
            }
        }

        func elevation(_ key: String) -> Double? {
            (metadata?[key] as? HKQuantity).flatMap { $0.is(compatibleWith: .meter()) ? $0.doubleValue(for: .meter()) : nil }
        }

        return Workout(id: workout.uuid, kind: kind,
                       activityName: WorkoutNaming.activityName(for: activityType, isIndoor: isIndoor),
                       title: WorkoutNaming.title(from: metadata),
                       start: workout.startDate, end: workout.endDate, duration: workout.duration,
                       activeEnergyKilocalories: active,
                       totalEnergyKilocalories: active.map { $0 + (basal ?? 0) },
                       averageHeartRate: averageHeartRate, maxHeartRate: maxHeartRate,
                       distanceMeters: distance.flatMap { $0 > 0 ? $0 : nil },
                       elevationGainMeters: elevation(HKMetadataKeyElevationAscended),
                       elevationLossMeters: elevation(HKMetadataKeyElevationDescended),
                       source: source, heartRateSource: heartRateSource,
                       isIndoor: isIndoor, hasRoute: hasRoute)
    }

    private func heartRateStatistics(in interval: DateInterval) async throws -> HKStatistics? {
        try await guarded(empty: nil) {
            let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
            let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HealthKitTypes.heartRate, predicate: predicate),
                                                         options: [.discreteAverage, .discreteMax, .separateBySource])
            return try await descriptor.result(for: store)
        }
    }

    private func routeExists(for workout: HKWorkout) async throws -> Bool {
        try await guarded(empty: false) {
            let descriptor = HKSampleQueryDescriptor(predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
                                                     sortDescriptors: [], limit: 1)
            return try await !descriptor.result(for: store).isEmpty
        }
    }

    // MARK: - Run details

    func route(for workoutID: UUID) async throws -> [RouteLocation] {
        guard isHealthDataAvailable else { throw HealthDataError.notFound }
        guard let workout = try await guarded(empty: nil, { try await hkWorkout(id: workoutID) }) else {
            throw HealthDataError.notFound
        }
        return try await routeLocations(for: workout)
    }

    func cumulativeDistance(for workoutID: UUID) async throws -> [MetricSample] {
        guard isHealthDataAvailable else { throw HealthDataError.notFound }
        let found = try await guarded(empty: nil) { try await hkWorkout(id: workoutID) }
        guard let workout = found, WorkoutKind(activityType: workout.workoutActivityType) == .run else {
            throw HealthDataError.notFound
        }
        let interval = DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))
        let buckets = try await bucketTotals(HealthKitTypes.distanceWalkingRunning, unit: .meter(), in: interval,
                                             every: DateComponents(second: Self.distanceBucketSeconds))
        return RunSeriesMath.cumulativeDistance(fromBuckets: buckets)
    }

    func runDetails(for workoutID: UUID) async throws -> RunDetails {
        guard isHealthDataAvailable else { throw HealthDataError.notFound }
        let found = try await guarded(empty: nil) { try await hkWorkout(id: workoutID) }
        guard let workout = found, WorkoutKind(activityType: workout.workoutActivityType) == .run else {
            throw HealthDataError.notFound
        }
        let interval = DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))

        async let route = routeLocations(for: workout)
        async let heartRate = optionalSeries(HealthKitTypes.heartRate, unit: RunningFormUnits.bpm, in: interval)
        async let speed = optionalSeries(HealthKitTypes.runningSpeed, unit: RunningFormUnits.metersPerSecond, in: interval)
        async let power = optionalSeries(HealthKitTypes.runningPower, unit: RunningFormUnits.watts, in: interval)
        async let stride = optionalSeries(HealthKitTypes.runningStrideLength, unit: RunningFormUnits.meters, in: interval)
        async let contact = optionalSeries(HealthKitTypes.runningGroundContactTime, unit: RunningFormUnits.milliseconds, in: interval)
        async let oscillation = optionalSeries(HealthKitTypes.runningVerticalOscillation, unit: RunningFormUnits.centimeters, in: interval)
        async let distanceBuckets = bucketTotals(HealthKitTypes.distanceWalkingRunning, unit: .meter(), in: interval,
                                                 every: DateComponents(second: Self.distanceBucketSeconds))
        async let stepBuckets = bucketTotals(HealthKitTypes.stepCount, unit: RunningFormUnits.count, in: interval,
                                             every: DateComponents(minute: 1))

        let cumulative = RunSeriesMath.cumulativeDistance(fromBuckets: try await distanceBuckets)
        let speedSeries = try await speed
        let pace = speedSeries.isEmpty ? RunSeriesMath.paceSeries(fromCumulativeDistance: cumulative)
                                       : RunSeriesMath.paceSeries(fromSpeed: speedSeries)
        let steps = try await stepBuckets
        let cadence = RunSeriesMath.cadenceSeries(fromStepBuckets: steps, within: interval)
        let totalSteps = steps.reduce(0) { $0 + $1.value }
        let routePoints = try await route
        let (strideSeries, contactSeries, oscillationSeries, powerSeries) = try await (stride, contact, oscillation, power)

        let form = RunningFormSummary(
            cadence: totalSteps > 0 && workout.duration > 0 ? totalSteps / (workout.duration / 60) : RunSeriesMath.mean(cadence),
            strideLength: RunSeriesMath.mean(strideSeries),
            groundContactTime: RunSeriesMath.mean(contactSeries),
            verticalOscillation: RunSeriesMath.mean(oscillationSeries),
            power: RunSeriesMath.mean(powerSeries))

        // Route and cumulative distance stay raw (splits & best efforts need full resolution); chart series
        // are downsampled to `SeriesDownsampler.chartPointLimit` points.
        let chart = { (series: [MetricSample]) in SeriesDownsampler.downsample(series) }
        return RunDetails(workoutID: workoutID, route: routePoints,
                          heartRate: chart(try await heartRate), pace: chart(pace),
                          elevation: chart(RunSeriesMath.elevationSeries(from: routePoints)),
                          cumulativeDistance: cumulative, cadence: chart(cadence),
                          strideLength: chart(strideSeries), groundContactTime: chart(contactSeries),
                          verticalOscillation: chart(oscillationSeries), power: chart(powerSeries), form: form)
    }

    /// GPS route of a workout, streamed batch by batch from `HKWorkoutRouteQueryDescriptor`.
    private func routeLocations(for workout: HKWorkout) async throws -> [RouteLocation] {
        try await guarded(empty: []) {
            let routes = try await HKSampleQueryDescriptor(predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
                                                           sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)
            var locations: [RouteLocation] = []
            for route in routes {
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                    locations.append(RouteLocation(timestamp: location.timestamp,
                                                   latitude: location.coordinate.latitude,
                                                   longitude: location.coordinate.longitude,
                                                   altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                                                   horizontalAccuracy: location.horizontalAccuracy,
                                                   speed: location.speed >= 0 ? location.speed : nil))
                }
            }
            return RunSeriesMath.filteredRoute(locations)
        }
    }

    private func optionalSeries(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval) async throws -> [MetricSample] {
        try await guarded(empty: []) { try await seriesSamples(type, unit: unit, in: interval) }
    }

    // MARK: - Query helpers

    /// Runs `body`, turning "no data / not authorized" into `empty` and other HealthKit errors into
    /// `HealthDataError`. Returns `empty` when Health is unavailable.
    private func guarded<T: Sendable>(empty: T, _ body: () async throws -> T) async throws -> T {
        guard isHealthDataAvailable else { return empty }
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let mapped = HealthDataError.mapping(error) { throw mapped }
            return empty
        }
    }

    private func quantitySamples(_ type: HKQuantityType, in interval: DateInterval, options: HKQueryOptions = [],
                                 limit: Int? = nil, newestFirst: Bool = false) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: options)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: newestFirst ? .reverse : .forward)],
                                                 limit: limit)
        return try await descriptor.result(for: store)
    }

    private func metricSample(_ sample: HKQuantitySample, metric: HealthMetric) -> MetricSample? {
        guard let value = metric.canonicalValue(of: sample.quantity) else { return nil }
        return MetricSample(date: metric.datesSampleByEnd ? sample.endDate : sample.startDate, value: value,
                            sourceName: sample.device?.name ?? sample.sourceRevision.source.name)
    }

    /// Every individual quantity (including those inside quantity series samples) overlapping `interval`.
    private func seriesSamples(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval) async throws -> [MetricSample] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate),
                                                               options: .orderByQuantitySampleStartDate)
        var result: [MetricSample] = []
        for try await item in descriptor.results(for: store) {
            let date = item.dateInterval.start
            guard date >= interval.start, date <= interval.end, item.quantity.is(compatibleWith: unit) else { continue }
            result.append(MetricSample(date: date, value: item.quantity.doubleValue(for: unit)))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Statistics buckets of `type` over `interval`.
    private func statistics(_ type: HKQuantityType, options: HKStatisticsOptions, in interval: DateInterval,
                            anchor: Date, every components: DateComponents) async throws -> [HKStatistics] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let descriptor = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate),
                                                               options: options, anchorDate: anchor, intervalComponents: components)
        return try await descriptor.result(for: store).statistics()
    }

    /// One value per local day (sum or average), keyed by `LocalDay`. Days without data are absent.
    private func dailyValues(_ type: HKQuantityType, unit: HKUnit, options: HKStatisticsOptions,
                             in interval: DateInterval) async throws -> [LocalDay: Double] {
        try await guarded(empty: [:]) {
            let stats = try await statistics(type, options: options, in: interval, anchor: calendar.startOfDay(for: interval.start),
                                             every: DateComponents(day: 1))
            var result: [LocalDay: Double] = [:]
            for bucket in stats {
                let quantity = options.contains(.cumulativeSum) ? bucket.sumQuantity() : bucket.averageQuantity()
                guard let quantity, quantity.is(compatibleWith: unit) else { continue }
                result[LocalDay(bucket.startDate, calendar: calendar)] = quantity.doubleValue(for: unit)
            }
            return result
        }
    }

    /// Cumulative-sum buckets anchored at `interval.start` (e.g. 5-s distance, 1-min steps). Statistics
    /// deduplicate overlapping sources (iPhone + Watch), unlike raw samples.
    private func bucketTotals(_ type: HKQuantityType, unit: HKUnit, in interval: DateInterval,
                              every components: DateComponents) async throws -> [QuantityBucket] {
        try await guarded(empty: []) {
            try await statistics(type, options: .cumulativeSum, in: interval, anchor: interval.start, every: components)
                .compactMap { bucket in
                    guard let quantity = bucket.sumQuantity(), quantity.is(compatibleWith: unit) else { return nil }
                    return QuantityBucket(interval: DateInterval(start: bucket.startDate, end: bucket.endDate), value: quantity.doubleValue(for: unit))
                }
        }
    }

    /// Hourly averages of `metric` (used for long heart-rate ranges).
    private func hourlyAverages(of metric: HealthMetric, in interval: DateInterval) async throws -> [MetricSample] {
        let anchor = calendar.dateInterval(of: .hour, for: interval.start)?.start ?? interval.start
        return try await statistics(metric.quantityType, options: .discreteAverage, in: interval, anchor: anchor,
                                    every: DateComponents(hour: 1))
            .compactMap { bucket in
                guard let quantity = bucket.averageQuantity(), let value = metric.canonicalValue(of: quantity) else { return nil }
                return MetricSample(date: bucket.startDate, value: value)
            }
    }

    // MARK: - Updates

    func updates() -> AsyncStream<HealthDataUpdate> {
        // Newest-only buffering coalesces bursts (several observers fire together after a sync).
        let (stream, continuation) = AsyncStream.makeStream(of: HealthDataUpdate.self, bufferingPolicy: .bufferingNewest(1))
        guard isHealthDataAvailable else {
            continuation.finish()
            return stream
        }
        let store = store
        let tracker = HealthUpdateTracker()
        var queries: [HKObserverQuery] = []
        for entry in HealthKitTypes.observed {
            let category = entry.category
            let query = HKObserverQuery(sampleType: entry.type, predicate: nil) { _, completionHandler, error in
                // HealthKit is told we're done once the consumer has refreshed (or after a timeout), so iOS keeps a
                // background launch alive for the work but never waits forever.
                let handler = ObserverCompletionHandler(completionHandler)
                let gate = ObserverCompletionGate(completion: { handler() })
                switch ObserverOutcome.classify(error) {
                case .signal:
                    let update = HealthDataUpdate(categories: [category], receivedAt: .now, acknowledge: { gate.acknowledge() })
                    switch continuation.yield(update) {
                    case .enqueued: break
                    case .dropped(let replaced): replaced.acknowledge() // superseded by a newer update
                    case .terminated: gate.acknowledge()
                    @unknown default: gate.acknowledge()
                    }
                case .deferUntilUnlock:
                    // Locked device: remember and re-signal once protected data is available again.
                    tracker.markPending(category)
                    gate.acknowledge()
                case .ignore:
                    gate.acknowledge()
                }
            }
            store.execute(query)
            queries.append(query)
        }

        // Updates that arrive while the device is locked can't be read; re-signal them after unlock.
        let unlockTask = Task {
            for await _ in NotificationCenter.default.notifications(named: UIApplication.protectedDataDidBecomeAvailableNotification)
                .map({ _ in () }) {
                let pending = tracker.takePending()
                if !pending.isEmpty { continuation.yield(HealthDataUpdate(categories: pending, receivedAt: .now)) }
            }
        }

        let running = queries
        continuation.onTermination = { _ in
            unlockTask.cancel()
            for query in running { store.stop(query) }
        }

        Task {
            for entry in HealthKitTypes.observed {
                // Fails without the background-delivery entitlement (e.g. unsigned builds); observers still work
                // while the app runs. Only sleep, workouts and HRV wake the app in the background.
                if let frequency = entry.backgroundFrequency {
                    try? await store.enableBackgroundDelivery(for: entry.type, frequency: frequency)
                } else {
                    try? await store.disableBackgroundDelivery(for: entry.type)
                }
            }
        }
        return stream
    }
}

/// Categories signalled since the last unlock (thread-safe; shared with observer callbacks).
final class HealthUpdateTracker: Sendable {
    private let pending = Mutex<Set<HealthDataCategory>>([])

    func markPending(_ category: HealthDataCategory) {
        pending.withLock { _ = $0.insert(category) }
    }

    func takePending() -> Set<HealthDataCategory> {
        pending.withLock { value in
            defer { value.removeAll() }
            return value
        }
    }
}

/// Resumes a continuation exactly once; later calls are ignored.
final class ResumeOnce<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = Mutex(continuation)
    }

    func callAsFunction(_ value: Value) {
        continuation.withLock { stored in
            stored?.resume(returning: value)
            stored = nil
        }
    }
}

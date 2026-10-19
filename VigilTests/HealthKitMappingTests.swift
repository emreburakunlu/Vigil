import Foundation
import HealthKit
import Testing
@testable import Vigil

@Suite("HealthKit · mapping & units")
struct HealthKitMappingTests {
    @Test func sleepStageMapping() {
        #expect(SleepStage(sleepAnalysisValue: HKCategoryValueSleepAnalysis.inBed.rawValue) == .inBed)
        #expect(SleepStage(sleepAnalysisValue: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue) == .asleepUnspecified)
        #expect(SleepStage(sleepAnalysisValue: HKCategoryValueSleepAnalysis.awake.rawValue) == .awake)
        #expect(SleepStage(sleepAnalysisValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue) == .core)
        #expect(SleepStage(sleepAnalysisValue: HKCategoryValueSleepAnalysis.asleepDeep.rawValue) == .deep)
        #expect(SleepStage(sleepAnalysisValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue) == .rem)
        #expect(SleepStage(sleepAnalysisValue: 99) == nil)
    }

    @Test(arguments: [
        (HKWorkoutActivityType.running, WorkoutKind.run),
        (.traditionalStrengthTraining, .strength),
        (.functionalStrengthTraining, .strength),
        (.coreTraining, .strength),
        (.walking, .other),
        (.cycling, .other),
        (.highIntensityIntervalTraining, .other),
        (.yoga, .other),
    ])
    func workoutKindMapping(type: HKWorkoutActivityType, kind: WorkoutKind) {
        #expect(WorkoutKind(activityType: type) == kind)
    }

    @Test func kindActivityTypesRoundTrip() {
        for kind in [WorkoutKind.run, .strength] {
            #expect(kind.activityTypes?.allSatisfy { WorkoutKind(activityType: $0) == kind } == true)
        }
        #expect(WorkoutKind.other.activityTypes == nil)
    }

    @Test func activityNames() {
        #expect(WorkoutNaming.activityName(for: .running, isIndoor: false) == "Outdoor Run")
        #expect(WorkoutNaming.activityName(for: .running, isIndoor: true) == "Indoor Run")
        #expect(WorkoutNaming.activityName(for: .traditionalStrengthTraining, isIndoor: true) == "Traditional Strength Training")
        #expect(WorkoutNaming.activityName(for: .functionalStrengthTraining, isIndoor: true) == "Functional Strength Training")
        #expect(WorkoutNaming.activityName(for: .archery, isIndoor: false) == "Workout")
    }

    @Test func titleFromMetadata() {
        #expect(WorkoutNaming.title(from: nil) == nil)
        #expect(WorkoutNaming.title(from: ["HKWorkoutTitle": "  Upper Body "]) == "Upper Body")
        #expect(WorkoutNaming.title(from: ["title": ""]) == nil)
        #expect(WorkoutNaming.title(from: [HKMetadataKeyIndoorWorkout: true]) == nil)
    }

    @Test func biologicalSexMapping() {
        #expect(BiologicalSex(HKBiologicalSex.female) == .female)
        #expect(BiologicalSex(HKBiologicalSex.male) == .male)
        #expect(BiologicalSex(HKBiologicalSex.other) == .other)
        #expect(BiologicalSex(HKBiologicalSex.notSet) == nil)
    }

    @Test func errorMapping() {
        #expect(HealthDataError.mapping(HKError(.errorDatabaseInaccessible)) == .protectedDataUnavailable)
        #expect(HealthDataError.mapping(HKError(.errorHealthDataUnavailable)) == .healthDataUnavailable)
        #expect(HealthDataError.mapping(HKError(.errorHealthDataRestricted)) == .healthDataUnavailable)
        #expect(HealthDataError.mapping(HKError(.errorNoData)) == nil)
        #expect(HealthDataError.mapping(HKError(.errorAuthorizationDenied)) == nil)
        #expect(HealthDataError.mapping(HKError(.errorAuthorizationNotDetermined)) == nil)
        #expect(HealthDataError.mapping(HealthDataError.notFound) == .notFound)
        let bridged = NSError(domain: HKErrorDomain, code: HKError.Code.errorDatabaseInaccessible.rawValue)
        #expect(HealthDataError.mapping(bridged) == .protectedDataUnavailable)
        if case .underlying = HealthDataError.mapping(HKError(.errorInvalidArgument)) {} else { Issue.record("expected .underlying") }
        if case .underlying = HealthDataError.mapping(URLError(.badURL)) {} else { Issue.record("expected .underlying") }
    }

    @Test func canonicalUnitConversions() throws {
        #expect(HealthMetric.oxygenSaturation.canonicalValue(of: HKQuantity(unit: .percent(), doubleValue: 0.97)) == 97)
        let hrv = try #require(HealthMetric.heartRateVariability.canonicalValue(of: HKQuantity(unit: .second(), doubleValue: 0.045)))
        #expect(abs(hrv - 45) < 1e-9)
        let temperature = try #require(HealthMetric.wristTemperature.canonicalValue(of: HKQuantity(unit: .degreeFahrenheit(), doubleValue: 98.6)))
        #expect(abs(temperature - 37) < 1e-9)
        let mass = try #require(HealthMetric.bodyMass.canonicalValue(of: HKQuantity(unit: .pound(), doubleValue: 176.37)))
        #expect(abs(mass - 80) < 0.01)
        let bpm = HKUnit.count().unitDivided(by: .second())
        #expect(HealthMetric.heartRate.canonicalValue(of: HKQuantity(unit: bpm, doubleValue: 1)) == 60)
        #expect(HealthMetric.respiratoryRate.canonicalValue(of: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 14.5)) == 14.5)
        let vo2 = HKUnit(from: "ml/kg*min")
        #expect(HealthMetric.vo2Max.canonicalValue(of: HKQuantity(unit: vo2, doubleValue: 52.3)) == 52.3)
        // Incompatible units are rejected rather than trapping.
        #expect(HealthMetric.bodyMass.canonicalValue(of: HKQuantity(unit: .meter(), doubleValue: 1)) == nil)
    }

    @Test func runningFormUnits() {
        #expect(HKQuantity(unit: .meter(), doubleValue: 0.092).doubleValue(for: RunningFormUnits.centimeters) == 9.2)
        #expect(abs(HKQuantity(unit: .second(), doubleValue: 0.245).doubleValue(for: RunningFormUnits.milliseconds) - 245) < 1e-9)
    }

    @Test func everyMetricHasACompatibleUnit() {
        for metric in HealthMetric.allCases {
            #expect(metric.quantityType.is(compatibleWith: metric.healthKitUnit), "\(metric)")
        }
    }

    @Test func readTypesAreComplete() {
        let types = HealthKitTypes.readTypes
        for metric in HealthMetric.allCases { #expect(types.contains(metric.quantityType)) }
        #expect(types.contains(HealthKitTypes.sleepAnalysis))
        #expect(types.contains(HealthKitTypes.workout))
        #expect(types.contains(HealthKitTypes.workoutRoute))
        #expect(types.contains(HealthKitTypes.activitySummary))
        #expect(types.contains(HealthKitTypes.dateOfBirth))
        for entry in HealthKitTypes.observed { #expect(types.contains(entry.type)) }
    }

    @Test func appleWatchDetection() {
        #expect(SampleSourceClassifier.isAppleWatch(productType: "Watch7,5", deviceModel: nil))
        #expect(SampleSourceClassifier.isAppleWatch(productType: nil, deviceModel: "Watch"))
        #expect(!SampleSourceClassifier.isAppleWatch(productType: "iPhone18,1", deviceModel: "iPhone"))
        #expect(!SampleSourceClassifier.isAppleWatch(productType: nil, deviceModel: nil))
    }

    @Test func updateTrackerTakesPendingOnce() {
        let tracker = HealthUpdateTracker()
        tracker.markPending(.sleep)
        tracker.markPending(.workouts)
        tracker.markPending(.sleep)
        #expect(tracker.takePending() == [.sleep, .workouts])
        #expect(tracker.takePending().isEmpty)
    }
}

@Suite("HealthKit · ResumeOnce")
struct HealthKitResumeOnceTests {
    @Test func firstValueWins() async {
        let value: Int = await withCheckedContinuation { continuation in
            let resume = ResumeOnce(continuation)
            resume(1)
            resume(2)
        }
        #expect(value == 1)
    }
}

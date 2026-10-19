import Foundation
import HealthKit

/// The HealthKit object types Vigil reads, and how they map to `HealthMetric` / `HealthDataCategory`.
/// Read-only: Vigil never requests share (write) access.
enum HealthKitTypes {
    // MARK: Quantity types

    static let heartRate = HKQuantityType(.heartRate)
    static let heartRateVariability = HKQuantityType(.heartRateVariabilitySDNN)
    static let restingHeartRate = HKQuantityType(.restingHeartRate)
    static let respiratoryRate = HKQuantityType(.respiratoryRate)
    static let wristTemperature = HKQuantityType(.appleSleepingWristTemperature)
    static let oxygenSaturation = HKQuantityType(.oxygenSaturation)
    static let stepCount = HKQuantityType(.stepCount)
    static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    static let basalEnergy = HKQuantityType(.basalEnergyBurned)
    static let exerciseTime = HKQuantityType(.appleExerciseTime)
    static let standTime = HKQuantityType(.appleStandTime)
    static let distanceWalkingRunning = HKQuantityType(.distanceWalkingRunning)
    static let runningSpeed = HKQuantityType(.runningSpeed)
    static let runningPower = HKQuantityType(.runningPower)
    static let runningStrideLength = HKQuantityType(.runningStrideLength)
    static let runningGroundContactTime = HKQuantityType(.runningGroundContactTime)
    static let runningVerticalOscillation = HKQuantityType(.runningVerticalOscillation)
    static let vo2Max = HKQuantityType(.vo2Max)
    static let bodyMass = HKQuantityType(.bodyMass)
    static let height = HKQuantityType(.height)

    // MARK: Other types

    static let sleepAnalysis = HKCategoryType(.sleepAnalysis)
    static let standHour = HKCategoryType(.appleStandHour)
    static let workout = HKObjectType.workoutType()
    static let workoutRoute = HKSeriesType.workoutRoute()
    static let activitySummary = HKObjectType.activitySummaryType()
    static let dateOfBirth = HKCharacteristicType(.dateOfBirth)
    static let biologicalSex = HKCharacteristicType(.biologicalSex)

    /// Everything shown on the Health permission sheet.
    static var readTypes: Set<HKObjectType> {
        [
            sleepAnalysis, standHour,
            heartRate, heartRateVariability, restingHeartRate, respiratoryRate, wristTemperature, oxygenSaturation,
            stepCount, activeEnergy, basalEnergy, exerciseTime, standTime,
            distanceWalkingRunning, runningSpeed, runningPower, runningStrideLength,
            runningGroundContactTime, runningVerticalOscillation,
            vo2Max, bodyMass, height,
            workout, workoutRoute, activitySummary,
            dateOfBirth, biologicalSex,
        ]
    }

    /// Observed sample types → the category they signal, with background-delivery frequency.
    ///
    /// Heart rate and steps are deliberately *not* observed: they change every few minutes and
    /// would trigger a recompute storm. Workouts carry the HR that matters for strain; active
    /// energy (hourly) carries everyday-movement changes.
    static let observed: [(type: HKSampleType, category: HealthDataCategory, frequency: HKUpdateFrequency)] = [
        (sleepAnalysis, .sleep, .immediate),
        (workout, .workouts, .immediate),
        (heartRateVariability, .heartRateVariability, .hourly),
        (restingHeartRate, .restingHeartRate, .hourly),
        (respiratoryRate, .respiratoryRate, .hourly),
        (wristTemperature, .wristTemperature, .hourly),
        (oxygenSaturation, .oxygenSaturation, .hourly),
        (activeEnergy, .activity, .hourly),
        (vo2Max, .vo2Max, .hourly),
        (bodyMass, .bodyMass, .hourly),
    ]
}

extension HealthMetric {
    /// The HealthKit quantity type backing this metric.
    var quantityType: HKQuantityType {
        switch self {
        case .heartRateVariability: HealthKitTypes.heartRateVariability
        case .restingHeartRate: HealthKitTypes.restingHeartRate
        case .respiratoryRate: HealthKitTypes.respiratoryRate
        case .wristTemperature: HealthKitTypes.wristTemperature
        case .oxygenSaturation: HealthKitTypes.oxygenSaturation
        case .heartRate: HealthKitTypes.heartRate
        case .vo2Max: HealthKitTypes.vo2Max
        case .bodyMass: HealthKitTypes.bodyMass
        }
    }

    /// The HealthKit unit read for this metric (before `canonicalScale`).
    var healthKitUnit: HKUnit {
        switch self {
        case .heartRateVariability: .secondUnit(with: .milli)
        case .restingHeartRate, .heartRate, .respiratoryRate: HKUnit.count().unitDivided(by: .minute())
        case .wristTemperature: .degreeCelsius()
        case .oxygenSaturation: .percent()
        case .vo2Max: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .bodyMass: .gramUnit(with: .kilo)
        }
    }

    /// Multiplier from `healthKitUnit` to the canonical unit (HealthKit's percent is a 0–1 fraction).
    var canonicalScale: Double { self == .oxygenSaturation ? 100 : 1 }

    /// Canonical value of a HealthKit quantity, or nil when the quantity is not compatible.
    func canonicalValue(of quantity: HKQuantity) -> Double? {
        guard quantity.is(compatibleWith: healthKitUnit) else { return nil }
        return quantity.doubleValue(for: healthKitUnit) * canonicalScale
    }

    /// Whether a sample's *end* date dates it. Sleeping wrist temperature spans the whole night and
    /// belongs to the wake day, so its end date is used; everything else uses the start date.
    var datesSampleByEnd: Bool { self == .wristTemperature }
}

/// Units for the running-form series (canonical units documented on `RunDetails`).
enum RunningFormUnits {
    static let metersPerSecond = HKUnit.meter().unitDivided(by: .second())
    static let watts = HKUnit.watt()
    static let meters = HKUnit.meter()
    static let milliseconds = HKUnit.secondUnit(with: .milli)
    static let centimeters = HKUnit.meterUnit(with: .centi)
    static let count = HKUnit.count()
    static let bpm = HKUnit.count().unitDivided(by: .minute())
    static let kilocalories = HKUnit.kilocalorie()
    static let minutes = HKUnit.minute()
}

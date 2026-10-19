import Foundation
import HealthKit

// Pure mappings from HealthKit values to Vigil's domain types. Unit-tested in `HealthKitMappingTests`.

extension SleepStage {
    /// Maps a raw `HKCategoryValueSleepAnalysis` value; nil for values Vigil doesn't know (future stages).
    init?(sleepAnalysisValue rawValue: Int) {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .inBed: self = .inBed
        case .asleepUnspecified: self = .asleepUnspecified
        case .awake: self = .awake
        case .asleepCore: self = .core
        case .asleepDeep: self = .deep
        case .asleepREM: self = .rem
        default: return nil
        }
    }
}

extension WorkoutKind {
    /// Vigil's coarse kind for a HealthKit activity type.
    ///
    /// Strength = traditional + functional strength training and core training (Hevy, Strong and the
    /// Workout app use these); everything else (walks, HIIT, cycling, …) is `.other`.
    init(activityType: HKWorkoutActivityType) {
        switch activityType {
        case .running: self = .run
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: self = .strength
        default: self = .other
        }
    }

    /// HealthKit activity types that make up this kind (nil for `.other`, which is "everything else").
    var activityTypes: [HKWorkoutActivityType]? {
        switch self {
        case .run: [.running]
        case .strength: [.traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining]
        case .other: nil
        }
    }
}

enum WorkoutNaming {
    /// English activity name in the style of the Fitness app ("Outdoor Run", "Traditional Strength Training").
    /// HealthKit has no public localized-name API; unknown types fall back to "Workout".
    static func activityName(for type: HKWorkoutActivityType, isIndoor: Bool) -> String {
        switch type {
        case .running: isIndoor ? "Indoor Run" : "Outdoor Run"
        case .walking: isIndoor ? "Indoor Walk" : "Outdoor Walk"
        case .cycling: isIndoor ? "Indoor Cycle" : "Outdoor Cycle"
        case .hiking: "Hiking"
        case .swimming: "Swimming"
        case .traditionalStrengthTraining: "Traditional Strength Training"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .coreTraining: "Core Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .crossTraining: "Cross Training"
        case .mixedCardio: "Mixed Cardio"
        case .elliptical: "Elliptical"
        case .rowing: "Rower"
        case .stairClimbing, .stairs: "Stair Stepper"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .flexibility: "Flexibility"
        case .cooldown: "Cooldown"
        case .preparationAndRecovery: "Recovery"
        case .cardioDance, .socialDance: "Dance"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .boxing, .kickboxing: "Kickboxing"
        case .martialArts: "Martial Arts"
        case .climbing: "Climbing"
        case .jumpRope: "Jump Rope"
        case .golf: "Golf"
        case .crossCountrySkiing, .downhillSkiing, .snowSports: "Skiing"
        case .snowboarding: "Snowboarding"
        default: "Workout"
        }
    }

    /// Metadata keys some apps use for a user-visible workout title. HealthKit has no standard key;
    /// Hevy/Strong/Strava behaviour must be verified on device.
    static let titleMetadataKeys = ["HKWorkoutTitle", "HKMetadataKeyWorkoutTitle", "title", "Title", "name", "workoutName", "WorkoutName"]

    /// A non-empty title from `metadata`, if any.
    static func title(from metadata: [String: Any]?) -> String? {
        guard let metadata else { return nil }
        for key in titleMetadataKeys {
            if let value = metadata[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

extension BiologicalSex {
    /// nil when not set in Health.
    init?(_ value: HKBiologicalSex) {
        switch value {
        case .female: self = .female
        case .male: self = .male
        case .other: self = .other
        case .notSet: return nil
        @unknown default: return nil
        }
    }
}

extension HealthDataError {
    /// Maps any error thrown by HealthKit into the contract's error type.
    /// Returns nil for "no data / not authorized" conditions, which the contract treats as empty results.
    static func mapping(_ error: any Error) -> HealthDataError? {
        if let error = error as? HealthDataError { return error }
        guard let hkError = error as? HKError else {
            let nsError = error as NSError
            if nsError.domain == HKErrorDomain, let code = HKError.Code(rawValue: nsError.code) {
                return mapping(HKError(code))
            }
            return .underlying(error.localizedDescription)
        }
        switch hkError.code {
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: return .healthDataUnavailable
        case .errorDatabaseInaccessible: return .protectedDataUnavailable
        case .errorNoData, .errorAuthorizationDenied, .errorAuthorizationNotDetermined, .errorRequiredAuthorizationDenied:
            return nil
        default: return .underlying(hkError.localizedDescription)
        }
    }
}

extension DataSourceInfo {
    /// Builds source info from a sample's source revision and device.
    init(sourceRevision: HKSourceRevision, device: HKDevice?) {
        self.init(name: sourceRevision.source.name, bundleIdentifier: sourceRevision.source.bundleIdentifier,
                  deviceName: device?.name)
    }
}

enum SampleSourceClassifier {
    /// Whether a sample was recorded by an Apple Watch (`productType` "Watch7,1…" or device model "Watch").
    static func isAppleWatch(productType: String?, deviceModel: String?) -> Bool {
        (productType?.hasPrefix("Watch") ?? false) || deviceModel == "Watch"
    }
}

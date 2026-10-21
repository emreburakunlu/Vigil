import Foundation

// Lifting sessions logged in Vigil itself (movement, sets, reps, weight). Stored locally by
// `LiftLogStore`; independent of the HealthKit strength workouts shown alongside them.

/// One set of an exercise. Weight is always stored in kilograms; convert only for display.
struct LoggedSet: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var reps: Int
    var weightKilograms: Double
    var isCompleted: Bool = false

    /// Weight × reps, kg.
    var volumeKilograms: Double { weightKilograms * Double(reps) }
}

/// A movement performed in a session with its sets, in order.
struct LoggedExercise: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sets: [LoggedSet] = []

    var completedSets: [LoggedSet] { sets.filter(\.isCompleted) }
    /// Heaviest completed set, by weight then reps.
    var bestSet: LoggedSet? { completedSets.max { ($0.weightKilograms, $0.reps) < ($1.weightKilograms, $1.reps) } }
}

/// A lifting session. `end == nil` means it is in progress.
struct LiftSession: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var title: String
    var start: Date
    var end: Date?
    var exercises: [LoggedExercise] = []
    var notes: String?

    var isActive: Bool { end == nil }
    var completedSetCount: Int { exercises.reduce(0) { $0 + $1.completedSets.count } }
    /// Total completed volume (weight × reps), kg.
    var totalVolumeKilograms: Double {
        exercises.reduce(0) { $0 + $1.completedSets.reduce(0) { $0 + $1.volumeKilograms } }
    }
    /// Elapsed seconds at `now` (or the full duration once finished).
    func duration(at now: Date = .now) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
}

/// Built-in movement names offered when adding an exercise (users can also type their own).
enum ExerciseCatalog {
    static let common: [String] = [
        "Back Squat", "Front Squat", "Deadlift", "Romanian Deadlift", "Bench Press", "Incline Bench Press",
        "Dumbbell Bench Press", "Overhead Press", "Dumbbell Shoulder Press", "Barbell Row", "Dumbbell Row",
        "Pull-Up", "Chin-Up", "Lat Pulldown", "Seated Cable Row", "Dip", "Push-Up", "Leg Press", "Lunge",
        "Bulgarian Split Squat", "Hip Thrust", "Leg Curl", "Leg Extension", "Calf Raise", "Bicep Curl",
        "Hammer Curl", "Tricep Pushdown", "Skull Crusher", "Lateral Raise", "Face Pull", "Chest Fly", "Plank",
    ]
}

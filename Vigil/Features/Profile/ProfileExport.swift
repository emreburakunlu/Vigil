import Foundation

/// Everything Vigil exports ("Export all data"). Canonical metric units throughout.
struct ProfileExportData: Codable, Sendable {
    var exportedAt: Date
    var appVersion: String
    var units: String
    var dailySummaries: [DailySummary]
    var workouts: [Workout]
}

/// Builds CSV and JSON exports (pure, unit-tested).
enum ProfileExporter {
    static let dailyHeader = ["date", "recovery_percent", "sleep_score", "sleep_seconds", "strain", "training_load",
                              "hrv_ms", "resting_hr_bpm", "respiratory_rate", "wrist_temp_c", "spo2_percent",
                              "steps", "active_kcal"]
    static let workoutHeader = ["id", "kind", "name", "start", "end", "duration_seconds", "distance_meters",
                                "active_kcal", "avg_hr_bpm", "max_hr_bpm", "source"]

    /// Quotes a field when it contains a comma, quote or newline.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ fields: [String]) -> String { fields.map(escape).joined(separator: ",") }

    static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    static func dailyCSV(_ summaries: [DailySummary]) -> String {
        var lines = [line(dailyHeader)]
        for s in summaries.sorted(by: { $0.day < $1.day }) {
            lines.append(line([
                s.day.isoString, number(s.recovery.map { Double($0.value) }), number(s.sleepScore.map { Double($0.value) }),
                number(s.sleepDuration), number(s.strain.map { Double($0.value) }), number(s.strain?.trainingLoad),
                number(s.vitals?.heartRateVariability), number(s.vitals?.restingHeartRate), number(s.vitals?.respiratoryRate),
                number(s.vitals?.wristTemperature), number(s.vitals?.oxygenSaturation),
                number(s.activity.map { Double($0.steps) }), number(s.activity?.activeEnergyKilocalories),
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func workoutsCSV(_ workouts: [Workout]) -> String {
        var lines = [line(workoutHeader)]
        for w in workouts.sorted(by: { $0.start < $1.start }) {
            lines.append(line([
                w.id.uuidString, w.kind.rawValue, w.displayName, w.start.formatted(.iso8601), w.end.formatted(.iso8601),
                number(w.duration), number(w.distanceMeters), number(w.activeEnergyKilocalories),
                number(w.averageHeartRate), number(w.maxHeartRate), w.source.name,
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ data: ProfileExportData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(data)
    }

    /// Files written to a fresh temporary folder, ready for `ShareLink`.
    struct Files: Sendable {
        var dailyCSV: URL
        var workoutsCSV: URL
        var json: URL
    }

    /// Runs off the main actor: encoding and disk writes never block the UI.
    @concurrent
    static func writeFiles(_ data: ProfileExportData, directory: URL = FileManager.default.temporaryDirectory) async throws -> Files {
        let folder = directory.appending(path: "VigilExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let daily = folder.appending(path: "vigil-daily.csv")
        let workouts = folder.appending(path: "vigil-workouts.csv")
        let json = folder.appending(path: "vigil-export.json")
        try Data(dailyCSV(data.dailySummaries).utf8).write(to: daily)
        try Data(workoutsCSV(data.workouts).utf8).write(to: workouts)
        try Self.json(data).write(to: json)
        return Files(dailyCSV: daily, workoutsCSV: workouts, json: json)
    }
}

import Foundation

/// Where a sample or workout came from ("Hevy", "Workout" on "Apple Watch Series 12").
struct DataSourceInfo: Hashable, Codable, Sendable {
    /// App name as reported by HealthKit (`HKSource.name`), e.g. "Hevy".
    var name: String
    /// App bundle identifier (`HKSource.bundleIdentifier`).
    var bundleIdentifier: String?
    /// Recording device display name, e.g. "Apple Watch Series 12" (`HKDevice.name`/model mapping).
    var deviceName: String?

    init(name: String, bundleIdentifier: String? = nil, deviceName: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
    }

    /// True when the bundle id belongs to Apple (Watch Workout app, Health, …).
    var isApple: Bool { bundleIdentifier?.hasPrefix("com.apple.") ?? false }
}

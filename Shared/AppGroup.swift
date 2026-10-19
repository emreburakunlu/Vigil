import Foundation

/// Identifiers shared by the app and the widget extension.
///
/// The App Group must be enabled on both targets (see `Config/*.entitlements`).
/// When the group container is unavailable (e.g. unsigned simulator builds with
/// `CODE_SIGNING_ALLOWED=NO`), callers fall back to a local directory so nothing crashes.
enum AppGroup {
    /// The App Group identifier registered for Vigil.
    static let identifier = "group.com.emreburakunlu.vigil"

    /// Root of the shared container, or `nil` if the entitlement is missing at runtime.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Shared container if available, otherwise this process' Application Support directory.
    /// The fallback is *not* visible to the other process; it only keeps unsigned builds working.
    static var containerURLOrFallback: URL {
        if let url = containerURL { return url }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "AppGroupFallback", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Widget `kind` strings. Used by the widget configurations and by the app to reload timelines.
    enum WidgetKind {
        static let recovery = "VigilRecoveryWidget"
        static let dailyScores = "VigilDailyScoresWidget"
        static let weeklyProgress = "VigilWeeklyProgressWidget"
    }
}

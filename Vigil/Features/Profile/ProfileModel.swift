import Foundation
import Observation
import UserNotifications

/// Screen model for Profile: data that is not a plain setting (Health state, export, re-import).
@MainActor
@Observable
final class ProfileModel {
    enum ExportState {
        case idle
        case preparing
        case ready(ProfileExporter.Files, days: Int, workouts: Int)
        case failed
    }

    private(set) var healthState: HealthAccessState?
    private(set) var healthBodyMass: Double?
    private(set) var cachedDays = 0
    private(set) var export: ExportState = .idle
    private(set) var importProgress: ImportProgress?
    private(set) var importFailed = false
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    func refreshNotificationStatus(container: AppContainer) async {
        notificationStatus = await container.notifications.authorizationStatus()
    }

    func load(container: AppContainer) async {
        cachedDays = container.summaries.count()
        healthState = await container.repository.healthAccessState()
        let repository = container.repository
        let end = repository.now()
        let start = end.addingTimeInterval(-180 * 86_400)
        let samples = try? await repository.dataSource.samples(of: .bodyMass, in: DateInterval(start: start, end: end))
        healthBodyMass = samples?.last?.value
    }

    func prepareExport(container: AppContainer) async {
        export = .preparing
        let repository = container.repository
        let today = repository.today
        let first = today.adding(days: -365, calendar: repository.calendar)
        do {
            let summaries = repository.summaries.summaries(from: first, through: today)
            let workouts = try await repository.dataSource.workouts(
                in: LocalDay.interval(from: first, through: today, calendar: repository.calendar), kinds: nil)
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let data = ProfileExportData(exportedAt: repository.now(), appVersion: version,
                                         units: "metric (m, kg, seconds, bpm, °C, kcal)", dailySummaries: summaries, workouts: workouts)
            export = .ready(try await ProfileExporter.writeFiles(data), days: summaries.count, workouts: workouts.count)
        } catch {
            export = .failed
        }
    }

    func reimport(container: AppContainer) async {
        importProgress = ImportProgress(phase: .sleep, fraction: 0, nightsImported: 0, workoutsImported: 0, workoutsTotal: 0)
        importFailed = false
        do {
            for try await event in container.importer.importHistory() { importProgress = event }
            cachedDays = container.summaries.count()
        } catch {
            importFailed = true
        }
    }

    func resetImport() {
        importProgress = nil
        importFailed = false
    }
}

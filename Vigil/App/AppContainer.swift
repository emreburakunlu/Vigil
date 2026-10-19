import Foundation
import Observation
import SwiftData
import SwiftUI

/// Dependency container. One per process (or per preview). Injected into the SwiftUI
/// environment by `VigilApp` / `.vigilPreview()`; read with `@Environment(AppContainer.self)`.
///
/// Screens normally need only `repository`, `settings` and `router`.
@MainActor
@Observable
final class AppContainer {
    let configuration: LaunchConfiguration
    let modelContainer: ModelContainer
    let dataSource: any HealthDataSource
    let engine: any ScoreEngine
    let settings: SettingsStore
    let summaries: DailySummaryStore
    let repository: VigilRepository
    let widgetSnapshots: WidgetSnapshotService
    let importer: HistoryImportService
    let notifications: NotificationService
    let router: AppRouter

    init(configuration: LaunchConfiguration, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { .now }) {
        self.configuration = configuration
        let modelContainer = PersistenceController.makeContainerOrFallback(configuration.storage)
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext
        if configuration.resetData {
            try? context.delete(model: SettingsRecord.self)
            try? context.delete(model: DailySummaryRecord.self)
            try? context.save()
        }
        switch configuration.dataMode {
        case .live:
            dataSource = LiveHealthDataSource()
        case .mock(let scenario):
            dataSource = MockHealthDataSource(scenario: scenario, referenceDate: now(), calendar: calendar)
        }
        engine = DefaultScoreEngine(calendar: calendar)
        settings = SettingsStore(container: modelContainer)
        summaries = DailySummaryStore(container: modelContainer)
        repository = VigilRepository(dataSource: dataSource, engine: engine, settings: settings, summaries: summaries,
                                     calendar: calendar, now: now)
        // Mock widgets write to a private directory so they never overwrite real data in the App Group.
        let snapshotStore = configuration.storage == .inMemory
            ? WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: "VigilPreviewSnapshot"))
            : WidgetSnapshotStore()
        widgetSnapshots = WidgetSnapshotService(repository: repository, store: snapshotStore)
        importer = HistoryImportService(repository: repository, widgetSnapshots: widgetSnapshots)
        notifications = NotificationService()
        router = AppRouter()
        widgetSnapshots.onSnapshot = { [notifications, settings] snapshot in
            await notifications.sync(settings: settings.settings, snapshot: snapshot)
        }
        if configuration.skipOnboarding {
            settings.update { $0.onboarding.completed = true }
        }
    }

    /// Container for this launch (see `LaunchConfiguration`).
    static func forCurrentLaunch() -> AppContainer {
        AppContainer(configuration: .current)
    }

    /// In-memory mock container for previews and tests.
    static func preview(_ scenario: MockScenario = .standard, onboarded: Bool = true) -> AppContainer {
        AppContainer(configuration: LaunchConfiguration(dataMode: .mock(scenario), storage: .inMemory,
                                                        skipOnboarding: onboarded, resetData: false))
    }

    /// Long-running work after launch: refresh recent days and follow HealthKit updates.
    /// Called from `VigilApp`'s root `.task`, so it is cancelled with the scene.
    /// Re-run with the onboarding flag as the task id so it starts as soon as onboarding finishes.
    func start() async {
        guard settings.settings.onboarding.completed else { return }
        await notifications.sync(settings: settings.settings, snapshot: widgetSnapshots.currentSnapshot())
        await refreshIfStale()
        await importer.observeHealthUpdates()
    }

    private var lastRefresh: Date?

    /// Recomputes recent days (and the widget snapshot) unless that happened in the last few minutes.
    /// Called at launch and whenever the app returns to the foreground, so the morning's new
    /// sleep shows up even if no HealthKit background update arrived.
    func refreshIfStale(minimumInterval: TimeInterval = 5 * 60) async {
        guard settings.settings.onboarding.completed else { return }
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < minimumInterval { return }
        lastRefresh = .now
        try? await importer.refreshRecent()
    }

    /// Settings that change scores, units or notification times were edited.
    func settingsDidChange() {
        widgetSnapshots.scheduleRefresh()
        Task { await notifications.sync(settings: settings.settings, snapshot: widgetSnapshots.currentSnapshot()) }
    }

    /// "Delete local data": removes cached scores/baselines and the widget snapshot and returns
    /// to onboarding. Apple Health data is never touched.
    func deleteAllLocalData() throws {
        try summaries.deleteAll()
        widgetSnapshots.clear()
        Task { await notifications.removeAll() }
        settings.resetToDefaults()
        router.reset()
    }
}

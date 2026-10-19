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
    func start() async {
        guard settings.settings.onboarding.completed else { return }
        try? await importer.refreshRecent()
        await importer.observeHealthUpdates()
    }

    /// "Delete local data": removes cached scores/baselines and the widget snapshot and returns
    /// to onboarding. Apple Health data is never touched.
    func deleteAllLocalData() throws {
        try summaries.deleteAll()
        widgetSnapshots.clear()
        settings.resetToDefaults()
        router.reset()
    }
}

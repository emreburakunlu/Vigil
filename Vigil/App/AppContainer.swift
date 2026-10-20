import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

/// Dependency container. One per process (or per preview). Injected into the SwiftUI
/// environment by `VigilApp` / `.vigilPreview()`; read with `@Environment(AppContainer.self)`.
///
/// Screens normally need only `repository`, `settings` and `router`, plus the two observable
/// change signals below for reloading:
///
/// ```swift
/// .task(id: [AnyHashable(selection), AnyHashable(container.dataVersion)]) { await model.load(...) }
/// .onChange(of: container.currentDay) { old, new in if selection == old { selection = new } }
/// ```
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

    /// Bumped whenever cached scores may have changed: after `refreshRecent`, the history import,
    /// `settingsDidChange()` and "Delete local data". Screens include it in their `.task(id:)`.
    private(set) var dataVersion = 0
    /// Today in the app's (auto-updating) calendar. Updated when the scene becomes active, at midnight
    /// (`NSCalendarDayChanged`), on significant time changes and time-zone changes.
    private(set) var currentDay: LocalDay

    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []

    init(configuration: LaunchConfiguration, calendar: Calendar = .autoupdatingCurrent, now: @escaping @Sendable () -> Date = { .now }) {
        self.configuration = configuration
        let modelContainer = PersistenceController.makeContainerOrFallback(configuration.storage)
        self.modelContainer = modelContainer
        let context = modelContainer.mainContext
        let personalBestURL: URL?
        switch configuration.storage {
        case .inMemory:
            personalBestURL = nil
        case .onDisk(let name):
            personalBestURL = PersonalBestCache.defaultURL(
                fileName: name == LaunchConfiguration.liveStoreName ? "PersonalBests.json" : "PersonalBests-\(name).json")
        }
        let personalBests = PersonalBestCache(fileURL: personalBestURL)
        if configuration.resetData {
            try? context.delete(model: SettingsRecord.self)
            try? context.delete(model: DailySummaryRecord.self)
            try? context.save()
            personalBests.reset()
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
                                     calendar: calendar, now: now, personalBestCache: personalBests)
        currentDay = LocalDay(now(), calendar: calendar)
        // Previews and tests never touch the App Group, WidgetCenter or the real notification center.
        let isEphemeral = configuration.storage == .inMemory
        let snapshotStore = isEphemeral
            ? WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory.appending(path: "VigilPreviewSnapshot-\(UUID().uuidString)"))
            : WidgetSnapshotStore()
        widgetSnapshots = isEphemeral
            ? WidgetSnapshotService(repository: repository, store: snapshotStore, reloadTimelines: {})
            : WidgetSnapshotService(repository: repository, store: snapshotStore)
        importer = HistoryImportService(repository: repository, widgetSnapshots: widgetSnapshots)
        notifications = isEphemeral
            ? NotificationService(scheduler: InMemoryNotificationScheduler(), calendar: calendar, now: now)
            : NotificationService(calendar: calendar, now: now)
        router = AppRouter()
        widgetSnapshots.onSnapshot = { [notifications, settings] snapshot in
            guard settings.settings.onboarding.completed else { return }
            await notifications.sync(settings: settings.settings, snapshot: snapshot)
        }
        importer.onDataChanged = { [weak self] in self?.noteDataChanged() }
        if configuration.skipOnboarding {
            settings.update { $0.onboarding.completed = true }
        }
    }

    /// The process-wide container (the app and its `UIApplicationDelegate` share it).
    static let shared = AppContainer.forCurrentLaunch()

    /// Container for this launch (see `LaunchConfiguration`).
    static func forCurrentLaunch() -> AppContainer {
        AppContainer(configuration: .current)
    }

    /// In-memory mock container for previews and tests.
    static func preview(_ scenario: MockScenario = .standard, onboarded: Bool = true) -> AppContainer {
        AppContainer(configuration: LaunchConfiguration(dataMode: .mock(scenario), storage: .inMemory,
                                                        skipOnboarding: onboarded, resetData: false))
    }

    private var isOnboarded: Bool { settings.settings.onboarding.completed }

    // MARK: Lifecycle

    /// Work after the scene appears (and again as soon as onboarding finishes, via the root `.task(id:)`):
    /// make sure HealthKit observation runs, sync notifications and refresh recent days.
    func start() async {
        guard isOnboarded else { return }
        startHealthObservation()
        await syncNotifications()
        await refreshIfStale()
    }

    /// Starts following HealthKit updates for the lifetime of the process (not the scene), so background
    /// deliveries are handled even when iOS launches the app without UI. Called from
    /// `application(_:didFinishLaunchingWithOptions:)` and from `start()`. No-op before onboarding.
    func startHealthObservation() {
        guard isOnboarded, observationTask == nil else { return }
        observationTask = Task { [importer] in await importer.observeHealthUpdates() }
    }

    /// Observes midnight, significant time changes and time-zone changes. Installed once at launch.
    func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let names: [Notification.Name] = [.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification,
                                          .NSSystemTimeZoneDidChange]
        for name in names {
            lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clockDidChange() }
            })
        }
    }

    /// The scene became active: roll `currentDay` over if needed and refresh if stale.
    func sceneDidBecomeActive() async {
        updateCurrentDay()
        await refreshIfStale()
    }

    /// Midnight, a time-zone change or a significant clock change: today is different, refresh now.
    func clockDidChange() {
        updateCurrentDay()
        repository.invalidateRecent()
        Task { await refreshIfStale(minimumInterval: 0) }
    }

    /// Recomputes `currentDay` from the clock.
    func updateCurrentDay() {
        let today = repository.today
        guard today != currentDay else { return }
        currentDay = today
        repository.invalidateRecent()
    }

    /// Scores may have changed; screens keyed on `dataVersion` reload.
    func noteDataChanged() {
        dataVersion &+= 1
    }

    /// Recomputes recent days (and the widget snapshot) unless that happened in the last few minutes.
    /// Called at launch and whenever the app returns to the foreground, so the morning's new
    /// sleep shows up even if no HealthKit background update arrived.
    func refreshIfStale(minimumInterval: TimeInterval = 5 * 60) async {
        guard isOnboarded else { return }
        let current = repository.now()
        if let lastRefresh, lastRefresh <= current, current.timeIntervalSince(lastRefresh) < minimumInterval { return }
        lastRefresh = current
        repository.invalidateRecent()
        try? await importer.refreshRecent()
    }

    /// Settings that change scores, units, zones or notification times were edited.
    /// Cached summaries carry a settings fingerprint, so changed scores rebuild on the next read.
    func settingsDidChange() {
        guard isOnboarded else { return }
        noteDataChanged()
        widgetSnapshots.scheduleRefresh()
        Task { await syncNotifications() }
    }

    /// Re-plans notifications with the last widget snapshot. No-op before onboarding.
    func syncNotifications() async {
        guard isOnboarded else { return }
        await notifications.sync(settings: settings.settings, snapshot: widgetSnapshots.currentSnapshot())
    }

    /// Onboarding finished: ask for notification permission when a notification is switched on, then schedule.
    func requestNotificationPermissionIfEnabled() async {
        let preferences = settings.settings.notifications
        guard preferences.morningSummaryEnabled || preferences.bedtimeReminderEnabled else { return }
        _ = await notifications.requestAuthorizationIfNeeded()
        await syncNotifications()
    }

    // MARK: Delete local data

    /// "Delete local data": resets settings (back to onboarding), removes cached scores/baselines,
    /// personal bests and the widget snapshot, and every scheduled notification. Apple Health data is
    /// never touched. Work that is in flight when this runs does not write anything afterwards.
    func deleteAllLocalData() async throws {
        try clearLocalState()
        await notifications.removeAll()
    }

    /// Synchronous variant for button actions; notification removal finishes in the background.
    func deleteAllLocalData() throws {
        try clearLocalState()
        Task { [notifications] in await notifications.removeAll() }
    }

    private func clearLocalState() throws {
        // Settings first: every refresh/sync path is guarded on `onboarding.completed`.
        settings.resetToDefaults()
        observationTask?.cancel()
        observationTask = nil
        lastRefresh = nil
        repository.resetCaches()
        widgetSnapshots.clear()
        defer {
            router.reset()
            noteDataChanged()
        }
        try summaries.deleteAll()
    }
}

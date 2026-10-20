import Foundation
import Observation

/// Onboarding screens in design order (Onb1…Onb7) plus the Health-access-denied state.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case scores
    case privacy
    case healthAccess
    case aboutYou
    case goals
    case historyImport
    case healthDenied

    /// 1…4 for the steps that show the four-segment progress bar.
    var progressStep: Int? {
        switch self {
        case .healthAccess: 1
        case .aboutYou: 2
        case .goals: 3
        case .historyImport: 4
        default: nil
        }
    }
}

/// Why requesting Health access did not lead anywhere.
enum OnboardingAccessProblem: Equatable {
    /// Health data does not exist on this device.
    case unavailable
    /// The permission request threw.
    case failed
}

/// State of the whole onboarding flow: navigation path, Health access request and the history import.
///
/// The import runs in a task owned by this model (not by the import screen), so it keeps going when
/// the user swipes back, and the screen simply re-attaches to the progress when it reappears.
@MainActor
@Observable
final class OnboardingModel {
    /// Steps pushed on top of the first welcome page.
    var path: [OnboardingStep]

    private(set) var isRequestingAccess = false
    private(set) var accessProblem: OnboardingAccessProblem?

    private(set) var importProgress: ImportProgress?
    private(set) var importFailed = false
    private(set) var importStartedAt: Date?
    @ObservationIgnored private var importTask: Task<Void, Never>?

    init(resumeFrom state: OnboardingState = .default) {
        path = Self.resumePath(for: state)
    }

    /// Where to resume after the app was killed mid-onboarding. The settings only record that Health
    /// access was requested and that the import finished, so the flow resumes at those coarse points.
    static func resumePath(for state: OnboardingState) -> [OnboardingStep] {
        if state.historyImportedAt != nil { return [.healthAccess, .aboutYou, .goals, .historyImport] }
        if state.healthAccessRequestedAt != nil { return [.healthAccess, .aboutYou] }
        return []
    }

    func push(_ step: OnboardingStep) { path.append(step) }

    func pop() { if !path.isEmpty { path.removeLast() } }

    // MARK: Health access

    /// Shows the Health permission sheet, then continues to About you, or to the denied state when
    /// nothing is readable afterwards.
    func requestHealthAccess(in container: AppContainer) async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        accessProblem = nil
        defer { isRequestingAccess = false }
        do {
            try await container.dataSource.requestAuthorization()
        } catch HealthDataError.healthDataUnavailable {
            accessProblem = .unavailable
            return
        } catch {
            accessProblem = .failed
            return
        }
        let now = container.repository.now()
        container.settings.update { $0.onboarding.healthAccessRequestedAt = now }
        await continueAfterAccessCheck(in: container, replacingDenied: false)
    }

    /// Re-checks access (after "Try again" or returning from Settings) and leaves the denied state when data is readable.
    func recheckHealthAccess(in container: AppContainer) async {
        await continueAfterAccessCheck(in: container, replacingDenied: true)
    }

    private func continueAfterAccessCheck(in container: AppContainer, replacingDenied: Bool) async {
        let state = await container.repository.healthAccessState()
        switch Self.destination(after: state) {
        case .denied:
            if path.last != .healthDenied { push(.healthDenied) }
        case .unavailable:
            accessProblem = .unavailable
        case .aboutYou:
            if replacingDenied, path.last == .healthDenied { pop() }
            if path.last != .aboutYou { push(.aboutYou) }
        }
    }

    enum AccessDestination: Equatable { case aboutYou, denied, unavailable }

    static func destination(after state: HealthAccessState) -> AccessDestination {
        switch state {
        case .likelyDenied: .denied
        case .unavailable: .unavailable
        case .connected, .notDetermined: .aboutYou
        }
    }

    // MARK: History import

    var isImporting: Bool { importTask != nil }

    var isImportFinished: Bool { importProgress?.phase == .finished }

    /// Starts the 90-day import once. Calling it again while running or after it finished does nothing.
    func startImport(in container: AppContainer) {
        guard importTask == nil, !isImportFinished else { return }
        if container.settings.settings.onboarding.historyImportedAt != nil {
            // Resumed after a kill: the import already finished. Count the imported nights from the cache.
            let repository = container.repository
            let today = repository.today
            let first = today.adding(days: -(HistoryImportService.defaultHistoryDays - 1), calendar: repository.calendar)
            let nights = repository.summaries.summaries(from: first, through: today).filter { $0.sleepNightID != nil }.count
            importProgress = ImportProgress(phase: .finished, fraction: 1, nightsImported: nights, workoutsImported: 0, workoutsTotal: 0)
            return
        }
        importFailed = false
        importProgress = nil
        importStartedAt = container.repository.now()
        importTask = Task { [weak self] in
            do {
                for try await event in container.importer.importHistory() { self?.importProgress = event }
            } catch {
                self?.importFailed = true
            }
            self?.importTask = nil
        }
    }

    func retryImport(in container: AppContainer) {
        guard !isImporting else { return }
        importFailed = false
        startImport(in: container)
    }

    /// Marks onboarding complete; `RootView` then shows the main tabs. When a notification is switched on
    /// (the morning summary is by default), asks for notification permission and schedules.
    func complete(in container: AppContainer) {
        container.settings.update { $0.onboarding.completed = true }
        Task { await container.requestNotificationPermissionIfEnabled() }
    }
}

/// State of one row of the import checklist.
enum ImportStepState: Equatable {
    case pending, active, done
}

/// Pure presentation logic of the import screen.
enum OnboardingImportPresentation {
    /// Checklist rows in order; each is active during the `ImportPhase` it names.
    static let rows: [ImportPhase] = [.sleep, .vitals, .workouts, .baselines, .scores]

    static func state(of row: ImportPhase, progress: ImportProgress?) -> ImportStepState {
        guard let progress else { return .pending }
        if progress.phase == .finished { return .done }
        guard let current = rows.firstIndex(of: progress.phase), let index = rows.firstIndex(of: row) else { return .pending }
        if index < current { return .done }
        return index == current ? .active : .pending
    }

    /// Seconds remaining, rounded up to 5 s, or nil while there is too little progress to estimate.
    static func secondsRemaining(fraction: Double, elapsed: TimeInterval) -> Int? {
        guard fraction >= 0.1, fraction < 1, elapsed >= 1 else { return nil }
        let remaining = elapsed * (1 - fraction) / fraction
        guard remaining.isFinite else { return nil }
        return max(5, Int((remaining / 5).rounded(.up)) * 5)
    }
}

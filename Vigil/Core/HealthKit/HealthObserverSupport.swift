import Foundation
import Synchronization

/// Calls a HealthKit observer `completionHandler` exactly once: either when the consumer acknowledges the update
/// (after it has refreshed), or when `timeout` elapses, whichever comes first. Thread-safe.
///
/// HealthKit keeps a background launch alive until the handler runs, but backs delivery off when it takes too long
/// (or never runs), hence the timeout.
final class ObserverCompletionGate: Sendable {
    /// Upper bound before the handler is called regardless of the consumer.
    static let defaultTimeout: Duration = .seconds(25)

    private let completion: Mutex<(@Sendable () -> Void)?>
    private let timeoutTask: Mutex<Task<Void, Never>?> = Mutex(nil)

    init(timeout: Duration = ObserverCompletionGate.defaultTimeout, completion: @escaping @Sendable () -> Void) {
        self.completion = Mutex(completion)
        let task = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.acknowledge()
        }
        timeoutTask.withLock { $0 = task }
    }

    /// Whether the completion has already run.
    var isCompleted: Bool { completion.withLock { $0 == nil } }

    /// Runs the completion the first time it is called; later calls are no-ops.
    func acknowledge() {
        let handler = completion.withLock { stored -> (@Sendable () -> Void)? in
            defer { stored = nil }
            return stored
        }
        guard let handler else { return }
        timeoutTask.withLock { task in
            task?.cancel()
            task = nil
        }
        handler()
    }
}

/// What an observer-query callback should do.
enum ObserverOutcome: Equatable, Sendable {
    /// New data: signal the consumer.
    case signal
    /// Device locked: remember the category and re-signal after unlock.
    case deferUntilUnlock
    /// Any other error: nothing to do.
    case ignore

    static func classify(_ error: Error?) -> ObserverOutcome {
        guard let error else { return .signal }
        return HealthDataError.mapping(error) == .protectedDataUnavailable ? .deferUntilUnlock : .ignore
    }
}

/// Immutable per-workout values that need extra HealthKit queries.
struct WorkoutDerived: Sendable, Equatable {
    var hasRoute: Bool
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var heartRateSource: DataSourceInfo?
}

/// Caches `WorkoutDerived` by workout UUID. HKWorkouts are immutable, so entries never need invalidating.
actor WorkoutDerivedCache {
    private var entries: [UUID: WorkoutDerived] = [:]

    func value(for id: UUID) -> WorkoutDerived? { entries[id] }

    func store(_ value: WorkoutDerived, for id: UUID) { entries[id] = value }

    var count: Int { entries.count }
}

/// Carries HealthKit's observer `completionHandler` (not annotated `Sendable`, but documented as callable from any
/// thread) into `ObserverCompletionGate`. The only `@unchecked Sendable` in the HealthKit layer; needs review.
struct ObserverCompletionHandler: @unchecked Sendable {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func callAsFunction() { handler() }
}

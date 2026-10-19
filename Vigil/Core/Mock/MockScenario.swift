import Foundation

/// Data situations the mock can simulate (drive the state screens and previews).
/// Select at launch with `-VigilMockScenario <rawValue>`.
enum MockScenario: String, CaseIterable, Codable, Sendable {
    /// ~1 year of plausible history: nightly sleep, vitals, 3 runs and 3–4 lifts a week.
    case standard
    /// First launch: permission not requested yet (`notDetermined` until `requestAuthorization()`),
    /// and only 3 days of data (today and the two days before).
    case newUser
    /// Permission requested but nothing readable (StateDenied).
    case healthAccessDenied
    /// No sleep recorded last night (StateNoSleep).
    case noSleepLastNight
    /// No runs in the last 7 days (StateNoRuns).
    case noRunsThisWeek
    /// No wrist temperature and no blood oxygen on any day, and no running power (StatePartial).
    case partialData
    /// Authorized, but Health is completely empty.
    case empty
    /// Illness-like dip today: short night, HRV far below baseline, elevated RHR / respiratory rate / wrist
    /// temperature, no training (red Recovery).
    case lowRecovery
    /// No strength workouts in the last 7 days (Lift tab empty state).
    case noLiftsThisWeek
}

import Foundation
import UserNotifications

// MARK: - Content

/// Values for the morning summary, taken from the freshly computed day.
struct MorningSummaryContent: Equatable, Sendable {
    /// Calendar day the scores belong to; the summary is only used for a notification firing that day.
    var day: Date
    var recoveryPercent: Int?
    var sleepDuration: TimeInterval?
    var readiness: ReadinessSuggestion?

    init(day: Date, recoveryPercent: Int?, sleepDuration: TimeInterval?, readiness: ReadinessSuggestion?) {
        self.day = day
        self.recoveryPercent = recoveryPercent
        self.sleepDuration = sleepDuration
        self.readiness = readiness
    }

    init(snapshot: WidgetSnapshot) {
        self.init(day: snapshot.day, recoveryPercent: snapshot.recoveryPercent,
                  sleepDuration: snapshot.sleepDuration, readiness: snapshot.readiness)
    }

    /// "Recovery 78% · Slept 7h 42m · Push day ready." Returns nil when there is nothing real to say.
    var body: String? {
        var parts: [String] = []
        if let recoveryPercent { parts.append("Recovery \(recoveryPercent)%") }
        if let sleepDuration, sleepDuration > 0 { parts.append("Slept \(VigilFormatter.duration(sleepDuration))") }
        guard !parts.isEmpty else { return nil }
        if let readiness {
            switch readiness {
            case .push: parts.append("Push day ready")
            case .maintain: parts.append("Maintain today")
            case .takeItEasy: parts.append("Take it easy today")
            }
        }
        return parts.joined(separator: " · ") + "."
    }
}

/// One notification the service will schedule.
struct PlannedNotification: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
    var components: DateComponents
    var repeats: Bool
}

/// Pure scheduling logic (testable without `UNUserNotificationCenter`).
///
/// Morning summary: a notification can't compute scores at delivery time (no push, no guaranteed
/// background run), so the app schedules the next `horizonDays` mornings as one-shot requests with
/// generic text and replaces today's with real values whenever fresh scores exist. The schedule is
/// rebuilt on every launch, settings change and data refresh; if the app isn't opened for
/// `horizonDays` days the morning notifications stop rather than repeat stale numbers.
enum NotificationPlanner {
    static let morningPrefix = "vigil.morning-summary"
    static let bedtimeIdentifier = "vigil.bedtime-reminder"
    static let horizonDays = 14

    static let genericMorningBody = "Open Vigil to see today's Recovery, Sleep and Strain."

    static func bedtimeBody(sleepTarget: TimeInterval) -> String {
        "Bedtime in 30 min to hit your \(VigilFormatter.duration(sleepTarget)) target."
    }

    static func plan(preferences: NotificationPreferences, sleepTarget: TimeInterval, morning: MorningSummaryContent?,
                     now: Date, calendar: Calendar = .current, horizonDays: Int = horizonDays) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        if preferences.morningSummaryEnabled {
            let startOfToday = calendar.startOfDay(for: now)
            for offset in 0..<horizonDays {
                guard let dayStart = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                      let fire = calendar.date(bySettingHour: preferences.morningSummaryMinutes / 60,
                                               minute: preferences.morningSummaryMinutes % 60, second: 0, of: dayStart),
                      fire > now else { continue }
                var body = NotificationPlanner.genericMorningBody
                if let morning, calendar.isDate(morning.day, inSameDayAs: fire), let real = morning.body { body = real }
                planned.append(PlannedNotification(
                    identifier: "\(morningPrefix).\(dayKey(dayStart, calendar: calendar))",
                    title: "Good morning", body: body,
                    components: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                    repeats: false))
            }
        }
        if preferences.bedtimeReminderEnabled {
            planned.append(PlannedNotification(
                identifier: bedtimeIdentifier, title: "Bedtime soon", body: bedtimeBody(sleepTarget: sleepTarget),
                components: DateComponents(hour: preferences.bedtimeReminderMinutes / 60, minute: preferences.bedtimeReminderMinutes % 60),
                repeats: true))
        }
        return planned
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Service

/// Schedules Vigil's local notifications (no push: a free Apple ID has no APNs).
///
/// - Permission is requested only through `requestAuthorizationIfNeeded()`, which the UI calls when the
///   user switches a notification on. `sync` never prompts; without permission it clears pending requests.
/// - `sync` is idempotent and cheap: call it on launch, on every settings change and after each data refresh.
@MainActor
final class NotificationService {
    private let center: UNUserNotificationCenter
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { .now }) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    /// Current OS authorization state.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks for alert/sound permission if it hasn't been decided yet. Call when the user enables a notification.
    /// Returns whether notifications are allowed (false when previously denied; the UI should point to Settings).
    func requestAuthorizationIfNeeded() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    /// Rebuilds all schedules from preferences. `morning` carries today's real values when known.
    func sync(preferences: NotificationPreferences, sleepTarget: TimeInterval, morning: MorningSummaryContent? = nil) async {
        await removeVigilRequests()
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        let plan = NotificationPlanner.plan(preferences: preferences, sleepTarget: sleepTarget, morning: morning,
                                            now: now(), calendar: calendar)
        for item in plan { await add(item) }
    }

    /// Convenience for the data-refresh path: re-plan using the freshly written snapshot.
    func sync(settings: VigilSettings, snapshot: WidgetSnapshot?) async {
        await sync(preferences: settings.notifications, sleepTarget: settings.goals.sleepTarget,
                   morning: snapshot.map(MorningSummaryContent.init(snapshot:)))
    }

    /// Removes everything Vigil scheduled (Delete local data).
    func removeAll() async { await removeVigilRequests() }

    private func removeVigilRequests() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.morningPrefix) || $0 == NotificationPlanner.bedtimeIdentifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func add(_ item: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = [NotificationDelegate.deepLinkKey: DeepLink.today.url.absoluteString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: item.components, repeats: item.repeats)
        do {
            try await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        } catch {
            print("Vigil: failed to schedule \(item.identifier): \(error)")
        }
    }
}

// MARK: - Tap handling

/// Routes a tapped notification to its `vigil://` URL (Today). Install once at launch:
/// `NotificationDelegate.install { url in router.handle(url) }`, before the first scene appears.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let deepLinkKey = "deepLink"
    nonisolated(unsafe) private static var shared: NotificationDelegate?

    private let handler: @MainActor @Sendable (URL) -> Void

    private init(handler: @escaping @MainActor @Sendable (URL) -> Void) { self.handler = handler }

    /// Sets the notification center delegate. Keeps a strong reference (the center holds it weakly).
    @MainActor
    static func install(center: UNUserNotificationCenter = .current(), handler: @escaping @MainActor @Sendable (URL) -> Void) {
        let delegate = NotificationDelegate(handler: handler)
        shared = delegate
        center.delegate = delegate
    }

    /// The URL carried by a notification's user info, defaulting to Today.
    static func url(from userInfo: [AnyHashable: Any]) -> URL {
        (userInfo[deepLinkKey] as? String).flatMap(URL.init(string:)) ?? DeepLink.today.url
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let url = Self.url(from: response.notification.request.content.userInfo)
        await MainActor.run { handler(url) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

import Foundation
import UserNotifications

/// Schedules Vigil's local notifications (no push). Owner: orchestrator / Profile agent.
///
/// - Morning summary: a daily repeating notification at `morningSummaryMinutes`; when fresh
///   scores exist (after a HealthKit sleep update), the content is replaced with
///   "Recovery 78% · Slept 7h 42m · Push day ready." via `scheduleMorningSummary(_:)`.
/// - Bedtime reminder: daily at `bedtimeReminderMinutes`.
@MainActor
final class NotificationService {
    static let morningIdentifier = "vigil.morning-summary"
    static let bedtimeIdentifier = "vigil.bedtime-reminder"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Asks for alert/sound permission. Returns whether notifications are allowed.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Re-creates both schedules from preferences. Safe to call often.
    func reschedule(_ preferences: NotificationPreferences, sleepTarget: TimeInterval) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningIdentifier, Self.bedtimeIdentifier])
        if preferences.morningSummaryEnabled {
            await add(id: Self.morningIdentifier, minutes: preferences.morningSummaryMinutes,
                      title: "Good morning", body: "Your Recovery, Sleep and Strain scores are ready.")
        }
        if preferences.bedtimeReminderEnabled {
            let hours = VigilFormatter.duration(sleepTarget, style: .hoursMinutes)
            await add(id: Self.bedtimeIdentifier, minutes: preferences.bedtimeReminderMinutes,
                      title: "Bedtime soon", body: "Head to bed in 30 min to hit your \(hours) target.")
        }
    }

    /// Replaces the morning summary content with today's numbers (called after scores update).
    func scheduleMorningSummary(_ text: String, at minutes: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningIdentifier])
        await add(id: Self.morningIdentifier, minutes: minutes, title: "Good morning", body: text)
    }

    private func add(id: String, minutes: Int, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["deepLink": DeepLink.today.url.absoluteString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            print("Vigil: failed to schedule \(id): \(error)")
        }
    }
}

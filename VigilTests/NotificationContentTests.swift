import Foundation
import Testing
@testable import Vigil

@Suite("Notification content and planning")
struct NotificationContentTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-10-19 06:00 UTC.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 6))! }
    var today: Date { calendar.startOfDay(for: now) }

    @Test func morningBodyWithAllValues() {
        let c = MorningSummaryContent(day: today, recoveryPercent: 78, sleepDuration: 7 * 3600 + 42 * 60, readiness: .push)
        #expect(c.body == "Recovery 78% · Slept 7h 42m · Push day ready.")
    }

    @Test func morningBodyOmitsMissingParts() {
        #expect(MorningSummaryContent(day: today, recoveryPercent: nil, sleepDuration: 8 * 3600, readiness: nil).body == "Slept 8h 00m.")
        #expect(MorningSummaryContent(day: today, recoveryPercent: 30, sleepDuration: nil, readiness: .takeItEasy).body == "Recovery 30% · Take it easy today.")
        #expect(MorningSummaryContent(day: today, recoveryPercent: nil, sleepDuration: nil, readiness: .push).body == nil)
    }

    @Test func bedtimeBodyUsesSleepTarget() {
        #expect(NotificationPlanner.bedtimeBody(sleepTarget: 8 * 3600) == "Bedtime in 30 min to hit your 8h 00m target.")
    }

    @Test func morningPlanSchedulesFutureDaysWithGenericText() {
        var prefs = NotificationPreferences.default
        prefs.bedtimeReminderEnabled = false
        let plan = NotificationPlanner.plan(preferences: prefs, sleepTarget: 8 * 3600, morning: nil, now: now, calendar: calendar)
        #expect(plan.count == NotificationPlanner.horizonDays)
        #expect(plan.allSatisfy { !$0.repeats && $0.body == NotificationPlanner.genericMorningBody })
        #expect(plan[0].components.day == 19 && plan[0].components.hour == 7 && plan[0].components.minute == 30)
        #expect(Set(plan.map(\.identifier)).count == plan.count)
    }

    @Test func todaysPlanIsSkippedOnceTimePassed() {
        let late = calendar.date(byAdding: .hour, value: 3, to: now)! // 09:00, after 07:30
        let plan = NotificationPlanner.plan(preferences: .default, sleepTarget: 8 * 3600, morning: nil, now: late, calendar: calendar)
        #expect(plan.first?.components.day == 20)
    }

    @Test func realValuesReplaceOnlyMatchingDay() {
        let content = MorningSummaryContent(day: today, recoveryPercent: 78, sleepDuration: 27_720, readiness: .push)
        let plan = NotificationPlanner.plan(preferences: .default, sleepTarget: 8 * 3600, morning: content, now: now, calendar: calendar)
        #expect(plan[0].body == "Recovery 78% · Slept 7h 42m · Push day ready.")
        #expect(plan[1].body == NotificationPlanner.genericMorningBody)
    }

    @Test func staleContentFromYesterdayIsNotUsed() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let content = MorningSummaryContent(day: yesterday, recoveryPercent: 50, sleepDuration: 3600, readiness: nil)
        let plan = NotificationPlanner.plan(preferences: .default, sleepTarget: 8 * 3600, morning: content, now: now, calendar: calendar)
        #expect(plan[0].body == NotificationPlanner.genericMorningBody)
    }

    @Test func bedtimeRepeatsDailyAtChosenTime() {
        var prefs = NotificationPreferences.default
        prefs.morningSummaryEnabled = false
        prefs.bedtimeReminderEnabled = true
        prefs.bedtimeReminderMinutes = 22 * 60 + 30
        let plan = NotificationPlanner.plan(preferences: prefs, sleepTarget: 8 * 3600, morning: nil, now: now, calendar: calendar)
        #expect(plan.count == 1)
        #expect(plan[0].repeats && plan[0].components.hour == 22 && plan[0].components.minute == 30)
        #expect(plan[0].identifier == NotificationPlanner.bedtimeIdentifier)
    }

    @Test func disabledPreferencesScheduleNothing() {
        var prefs = NotificationPreferences.default
        prefs.morningSummaryEnabled = false
        prefs.bedtimeReminderEnabled = false
        #expect(NotificationPlanner.plan(preferences: prefs, sleepTarget: 8 * 3600, morning: nil, now: now, calendar: calendar).isEmpty)
    }

    @Test func tapDeepLinkDefaultsToToday() {
        #expect(NotificationDelegate.url(from: [:]) == DeepLink.today.url)
        #expect(NotificationDelegate.url(from: ["deepLink": "vigil://sleep"]).absoluteString == "vigil://sleep")
    }
}

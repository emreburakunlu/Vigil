import Foundation
import Testing
@testable import Vigil

@Suite("ProfileLogic")
struct ProfileLogicTests {
    @Test func zoneBoundsMustAscend() {
        #expect(ProfileLogic.validateZoneBounds([117, 137, 156, 176], maxHeartRate: 193) == nil)
        #expect(ProfileLogic.validateZoneBounds([117, 117, 156, 176], maxHeartRate: 193) == .notAscending)
        #expect(ProfileLogic.validateZoneBounds([150, 140, 156, 176], maxHeartRate: 193) == .notAscending)
        #expect(ProfileLogic.validateZoneBounds([117, 137, 156, 193], maxHeartRate: 193) == .aboveMax)
        #expect(ProfileLogic.validateZoneBounds([10, 137, 156, 176], maxHeartRate: 193) == .tooLow)
        #expect(ProfileLogic.validateZoneBounds([117, 137], maxHeartRate: 193) == .wrongCount)
    }

    @Test func sleepTargetSnapsAndClamps() {
        #expect(ProfileLogic.clampedSleepTarget(8 * 3600 + 400) == 8 * 3600 + 900 || ProfileLogic.clampedSleepTarget(8 * 3600 + 400) == 8 * 3600)
        #expect(ProfileLogic.clampedSleepTarget(3 * 3600) == 5 * 3600)
        #expect(ProfileLogic.clampedSleepTarget(14 * 3600) == 11 * 3600)
    }

    @Test func minutesRoundTrip() {
        let calendar = TestSupport.utc
        let date = ProfileLogic.date(fromMinutes: 7 * 60 + 15, calendar: calendar, now: TestSupport.referenceDate)
        #expect(ProfileLogic.minutes(from: date, calendar: calendar) == 435)
        #expect(ProfileLogic.minutes(from: ProfileLogic.date(fromMinutes: 5000, calendar: calendar, now: TestSupport.referenceDate), calendar: calendar) == 24 * 60 - 1)
    }

    @Test func ageFromDateOfBirth() {
        let calendar = TestSupport.utc
        let birth = calendar.date(from: DateComponents(year: 2005, month: 3, day: 14))
        #expect(ProfileLogic.age(from: birth, now: TestSupport.referenceDate, calendar: calendar) == 21)
        #expect(ProfileLogic.age(from: nil, now: TestSupport.referenceDate, calendar: calendar) == nil)
    }

    @Test func bodyMassPlausibility() {
        #expect(ProfileLogic.isPlausibleBodyMass(kilograms: 78.4))
        #expect(!ProfileLogic.isPlausibleBodyMass(kilograms: 5))
    }
}

@Suite("ProfileExporter")
struct ProfileExporterTests {
    @Test func csvEscapesSpecialCharacters() {
        #expect(ProfileExporter.escape("plain") == "plain")
        #expect(ProfileExporter.escape("a,b") == "\"a,b\"")
        #expect(ProfileExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func dailyCSVHasHeaderAndRowPerDay() {
        var summary = DailySummary(day: LocalDay(year: 2026, month: 10, day: 19), sleepDuration: 27_000)
        summary.vitals = DailyVitals(day: summary.day, heartRateVariability: 68.4, restingHeartRate: 52)
        let csv = ProfileExporter.dailyCSV([summary])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("date,recovery_percent"))
        #expect(lines[1].hasPrefix("2026-10-19,,,27000,"))
        #expect(lines[1].contains("68.4,52"))
    }

    @Test func jsonRoundTripsAndFilesAreWritten() throws {
        let data = ProfileExportData(exportedAt: TestSupport.referenceDate, appVersion: "1.0", units: "metric",
                                     dailySummaries: [DailySummary(day: LocalDay(year: 2026, month: 10, day: 19))], workouts: [])
        let json = try ProfileExporter.json(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(ProfileExportData.self, from: json).dailySummaries.count == 1)
        let files = try ProfileExporter.writeFiles(data)
        #expect(FileManager.default.fileExists(atPath: files.dailyCSV.path()))
        #expect(FileManager.default.fileExists(atPath: files.workoutsCSV.path()))
        #expect(FileManager.default.fileExists(atPath: files.json.path()))
    }
}

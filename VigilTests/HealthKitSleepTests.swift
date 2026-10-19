import Foundation
import Testing
@testable import Vigil

@Suite("HealthKit · SleepNightBuilder")
struct HealthKitSleepTests {
    static let watch = DataSourceInfo(name: "Apple Watch", bundleIdentifier: "com.apple.health.ABC", deviceName: "Apple Watch")
    static let iPhone = DataSourceInfo(name: "iPhone", bundleIdentifier: "com.apple.health", deviceName: "iPhone")
    static let ring = DataSourceInfo(name: "SleepRing", bundleIdentifier: "com.example.ring")
    static let manual = DataSourceInfo(name: "Health", bundleIdentifier: "com.apple.Health")

    let calendar = TestSupport.utc

    /// Date on 2026-10-`day` at `hour`:`minute` in `calendar`.
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, in calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func sample(_ stage: SleepStage, _ start: Date, _ end: Date, _ source: DataSourceInfo = watch,
                priority: Int = SleepSourcePriority.appleWatch) -> RawSleepSample {
        RawSleepSample(stage: stage, start: start, end: end, source: source, priority: priority)
    }

    func builder(_ calendar: Calendar? = nil) -> SleepNightBuilder { SleepNightBuilder(calendar: calendar ?? self.calendar) }

    // MARK: Basics

    @Test func emptyInput() {
        #expect(builder().nights(from: []).isEmpty)
        #expect(SleepNightBuilder.mergeTimeline([]).isEmpty)
    }

    @Test func singleWatchNightCrossingMidnight() throws {
        let samples = [
            sample(.inBed, at(18, 22, 40), at(19, 7, 10), Self.iPhone, priority: SleepSourcePriority.otherApple),
            sample(.awake, at(18, 22, 45), at(18, 23, 0)), // sleep latency: dropped
            sample(.core, at(18, 23, 0), at(19, 1, 0)),
            sample(.deep, at(19, 1, 0), at(19, 2, 0)),
            sample(.awake, at(19, 2, 0), at(19, 2, 10)),
            sample(.rem, at(19, 2, 10), at(19, 4, 0)),
            sample(.core, at(19, 4, 0), at(19, 6, 50)),
            sample(.awake, at(19, 6, 50), at(19, 7, 5)), // after final wake: dropped
        ]
        let nights = builder().nights(from: samples)
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(night.day == LocalDay(year: 2026, month: 10, day: 19))
        #expect(night.id == "2026-10-19-primary")
        #expect(night.isPrimary)
        #expect(night.sleepStart == at(18, 23, 0))
        #expect(night.sleepEnd == at(19, 6, 50))
        #expect(night.inBedStart == at(18, 22, 40))
        #expect(night.inBedEnd == at(19, 7, 10))
        #expect(night.stageDurations.core == (120 + 170) * 60)
        #expect(night.stageDurations.deep == 60 * 60)
        #expect(night.stageDurations.rem == 110 * 60)
        #expect(night.stageDurations.awake == 10 * 60)
        #expect(night.interruptions == 1)
        #expect(night.segments.allSatisfy { $0.stage != .inBed })
        #expect(night.segments.first?.start == night.sleepStart)
        #expect(night.sources.first == Self.watch)
        #expect(night.sources.contains(Self.iPhone))
    }

    @Test func noInBedSamplesFallsBackToAsleepWindow() throws {
        let night = try #require(builder().nights(from: [sample(.asleepUnspecified, at(18, 23), at(19, 6))]).first)
        #expect(night.inBedStart == night.sleepStart)
        #expect(night.inBedEnd == night.sleepEnd)
        #expect(night.efficiency == 1)
        #expect(!night.hasStages)
        #expect(night.stageDurations.unspecified == 7 * 3600)
    }

    @Test func inBedOnlyProducesNoNight() {
        #expect(builder().nights(from: [sample(.inBed, at(18, 23), at(19, 7), Self.iPhone)]).isEmpty)
    }

    @Test func shortSessionIsIgnored() {
        #expect(builder().nights(from: [sample(.core, at(19, 3), at(19, 3, 5))]).isEmpty)
    }

    @Test func invalidSamplesAreIgnored() {
        #expect(builder().nights(from: [sample(.core, at(19, 7), at(19, 3))]).isEmpty)
    }

    // MARK: Multiple sources

    @Test func overlappingSourcesAreNotDoubleCounted() throws {
        let samples = [
            sample(.core, at(18, 23), at(19, 3)),
            sample(.deep, at(19, 3), at(19, 4)),
            sample(.rem, at(19, 4), at(19, 7)),
            // A third-party ring and a manual entry claim the same night.
            sample(.asleepUnspecified, at(18, 23, 30), at(19, 6, 30), Self.ring, priority: SleepSourcePriority.thirdParty),
            sample(.asleepUnspecified, at(18, 23), at(19, 7), Self.manual, priority: SleepSourcePriority.userEntered),
        ]
        let night = try #require(builder().nights(from: samples).first)
        #expect(night.asleepDuration == 8 * 3600)
        #expect(night.stageDurations.unspecified == 0)
        #expect(night.segments.allSatisfy { $0.source == Self.watch })
        #expect(night.sources == [Self.watch])
    }

    @Test func lowerPrioritySourceFillsGaps() throws {
        // Watch battery died at 03:00; the iPhone kept tracking.
        let samples = [
            sample(.core, at(18, 23), at(19, 3)),
            sample(.asleepUnspecified, at(18, 22, 30), at(19, 7), Self.iPhone, priority: SleepSourcePriority.otherApple),
        ]
        let night = try #require(builder().nights(from: samples).first)
        #expect(night.asleepDuration == 8.5 * 3600)
        #expect(night.stageDurations.core == 4 * 3600)
        #expect(night.stageDurations.unspecified == 4.5 * 3600)
        #expect(night.sources.first == Self.iPhone) // most asleep time
        #expect(night.sources.count == 2)
    }

    @Test func watchAwakeOverridesLowerPriorityAsleep() throws {
        let samples = [
            sample(.core, at(18, 23), at(19, 2)),
            sample(.awake, at(19, 2), at(19, 2, 20)),
            sample(.core, at(19, 2, 20), at(19, 6)),
            sample(.asleepUnspecified, at(18, 23), at(19, 6), Self.ring, priority: SleepSourcePriority.thirdParty),
        ]
        let night = try #require(builder().nights(from: samples).first)
        #expect(night.stageDurations.awake == 20 * 60)
        #expect(night.asleepDuration == 7 * 3600 - 20 * 60)
        #expect(night.interruptions == 1)
    }

    @Test func adjacentAwakeFromTwoSourcesIsOneInterruption() throws {
        let samples = [
            sample(.core, at(18, 23), at(19, 2)),
            sample(.awake, at(19, 2), at(19, 2, 10)),
            sample(.awake, at(19, 2, 10), at(19, 2, 20), Self.ring, priority: SleepSourcePriority.thirdParty),
            sample(.core, at(19, 2, 20), at(19, 4)),
            sample(.awake, at(19, 4), at(19, 4, 5)),
            sample(.rem, at(19, 4, 5), at(19, 6)),
        ]
        let night = try #require(builder().nights(from: samples).first)
        #expect(night.interruptions == 2)
        #expect(night.stageDurations.awake == 25 * 60)
    }

    @Test func mergeTimelineJoinsAdjacentSameStage() {
        let segments = SleepNightBuilder.mergeTimeline([
            sample(.core, at(19, 1), at(19, 2)),
            sample(.core, at(19, 2), at(19, 3)),
            sample(.rem, at(19, 3), at(19, 4)),
        ])
        #expect(segments.count == 2)
        #expect(segments[0].start == at(19, 1) && segments[0].end == at(19, 3))
        #expect(segments[1].stage == .rem)
    }

    @Test func sameSourceDuplicatesCollapse() throws {
        let duplicate = sample(.core, at(18, 23), at(19, 6))
        let night = try #require(builder().nights(from: [duplicate, duplicate]).first)
        #expect(night.asleepDuration == 7 * 3600)
    }

    // MARK: Day assignment, naps, sessions

    @Test func napIsSeparateNonPrimaryNight() throws {
        let samples = [
            sample(.core, at(18, 23), at(19, 7)),
            sample(.core, at(19, 14), at(19, 14, 40)),
        ]
        let nights = builder().nights(from: samples)
        #expect(nights.count == 2)
        let primary = try #require(nights.first { $0.isPrimary })
        let nap = try #require(nights.first(where: { !$0.isPrimary }))
        #expect(primary.id == "2026-10-19-primary")
        #expect(nap.id == "2026-10-19-nap-1400")
        #expect(nap.day == primary.day)
        #expect(nights.map(\.sleepEnd) == nights.map(\.sleepEnd).sorted())
    }

    @Test func daytimeNapAloneIsNotPrimary() throws {
        let nights = builder().nights(from: [sample(.core, at(19, 13), at(19, 14, 30))])
        let nap = try #require(nights.first)
        #expect(!nap.isPrimary)
    }

    @Test func longDaytimeSleepIsPrimary() throws {
        // Shift worker: 08:30 → 15:30 is the main sleep.
        let night = try #require(builder().nights(from: [sample(.core, at(19, 8, 30), at(19, 15, 30))]).first)
        #expect(night.isPrimary)
    }

    @Test func gapLongerThanTwoHoursSplitsSessions() {
        let nights = builder().nights(from: [
            sample(.core, at(18, 22), at(19, 0)),
            sample(.core, at(19, 2, 30), at(19, 7)),
        ])
        #expect(nights.count == 2)
        #expect(nights.filter(\.isPrimary).count == 1)
        #expect(nights.first(where: \.isPrimary)?.sleepStart == at(19, 2, 30))
    }

    @Test func shortGapStaysOneNight() throws {
        let nights = builder().nights(from: [
            sample(.core, at(18, 22), at(19, 0)),
            sample(.core, at(19, 1, 30), at(19, 7)),
        ])
        #expect(nights.count == 1)
        let night = try #require(nights.first)
        #expect(night.asleepDuration == 7.5 * 3600)
        #expect(night.interruptions == 0) // gaps without samples are not "awake"
    }

    @Test func wakingInFiltersByWakeTime() {
        let samples = [
            sample(.core, at(17, 23), at(18, 7)),
            sample(.core, at(18, 23), at(19, 7)),
        ]
        let monday = LocalDay(year: 2026, month: 10, day: 19).interval(in: calendar)
        let nights = builder().nights(from: samples, wakingIn: monday)
        #expect(nights.map(\.day) == [LocalDay(year: 2026, month: 10, day: 19)])
    }

    @Test func consecutiveNightsGetTheirOwnWakeDays() {
        let nights = builder().nights(from: [
            sample(.core, at(16, 23), at(17, 7)),
            sample(.core, at(17, 23), at(18, 7)),
            sample(.core, at(18, 23), at(19, 7)),
        ])
        #expect(nights.map(\.day.day) == [17, 18, 19])
        #expect(nights.allSatisfy { $0.isPrimary })
    }

    // MARK: Time zones & DST

    @Test func dstFallBackNightIsAnHourLonger() throws {
        // Europe/Berlin leaves DST on Sun 25 Oct 2026 at 03:00 → 02:00.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = at(24, 23, in: berlin), end = at(25, 7, in: berlin)
        let night = try #require(builder(berlin).nights(from: [sample(.core, start, end)]).first)
        #expect(night.asleepDuration == 9 * 3600)
        #expect(night.day == LocalDay(year: 2026, month: 10, day: 25))
        #expect(night.isPrimary)
    }

    @Test func dstSpringForwardNightIsAnHourShorter() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = at(28, 23, month: 3, in: berlin), end = at(29, 7, month: 3, in: berlin)
        let night = try #require(builder(berlin).nights(from: [sample(.core, start, end)]).first)
        #expect(night.asleepDuration == 7 * 3600)
        #expect(night.day == LocalDay(year: 2026, month: 3, day: 29))
    }

    @Test func wakeDayFollowsCalendarTimeZone() throws {
        // 05:30 UTC wake is still the previous evening in Los Angeles → different wake day.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let samples = [sample(.core, at(19, 0), at(19, 5, 30))]
        #expect(builder().nights(from: samples).first?.day == LocalDay(year: 2026, month: 10, day: 19))
        #expect(builder(la).nights(from: samples).first?.day == LocalDay(year: 2026, month: 10, day: 18))
    }

    // MARK: Priority

    @Test func sourcePriorityOrdering() {
        let watch = SleepSourcePriority.priority(isAppleWatch: true, isAppleBundle: true, isUserEntered: false)
        let ring = SleepSourcePriority.priority(isAppleWatch: false, isAppleBundle: false, isUserEntered: false)
        let phone = SleepSourcePriority.priority(isAppleWatch: false, isAppleBundle: true, isUserEntered: false)
        let manual = SleepSourcePriority.priority(isAppleWatch: false, isAppleBundle: true, isUserEntered: true)
        #expect(watch > ring && ring > phone && phone > manual)
    }
}

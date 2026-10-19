import Foundation
import Testing
@testable import Vigil

@MainActor
struct OnboardingTests {
    @Test func resumePathFollowsSettings() {
        #expect(OnboardingModel.resumePath(for: .default).isEmpty)
        var state = OnboardingState.default
        state.healthAccessRequestedAt = TestSupport.referenceDate
        #expect(OnboardingModel.resumePath(for: state) == [.healthAccess, .aboutYou])
        state.historyImportedAt = TestSupport.referenceDate
        #expect(OnboardingModel.resumePath(for: state).last == .historyImport)
    }

    @Test func accessDestinations() {
        #expect(OnboardingModel.destination(after: .likelyDenied) == .denied)
        #expect(OnboardingModel.destination(after: .connected) == .aboutYou)
        #expect(OnboardingModel.destination(after: .unavailable) == .unavailable)
    }

    @Test func importRowStates() {
        func progress(_ phase: ImportPhase) -> ImportProgress {
            ImportProgress(phase: phase, fraction: 0.5, nightsImported: 0, workoutsImported: 0, workoutsTotal: 0)
        }
        #expect(OnboardingImportPresentation.state(of: .sleep, progress: nil) == .pending)
        #expect(OnboardingImportPresentation.state(of: .sleep, progress: progress(.workouts)) == .done)
        #expect(OnboardingImportPresentation.state(of: .workouts, progress: progress(.workouts)) == .active)
        #expect(OnboardingImportPresentation.state(of: .scores, progress: progress(.workouts)) == .pending)
        #expect(OnboardingImportPresentation.state(of: .scores, progress: progress(.finished)) == .done)
    }

    @Test func secondsRemainingEstimate() {
        #expect(OnboardingImportPresentation.secondsRemaining(fraction: 0.05, elapsed: 10) == nil)
        #expect(OnboardingImportPresentation.secondsRemaining(fraction: 0.5, elapsed: 10) == 10)
        #expect(OnboardingImportPresentation.secondsRemaining(fraction: 0.9, elapsed: 30) == 5)
        #expect(OnboardingImportPresentation.secondsRemaining(fraction: 1, elapsed: 30) == nil)
    }

    @Test func goalSteppersSnapAndClamp() {
        let metric = VigilFormatter(units: .metric)
        let imperial = VigilFormatter(units: .imperial)
        #expect(OnboardingGoalSteps.steppedSleep(8 * 3600, by: 1) == 8.25 * 3600)
        #expect(OnboardingGoalSteps.steppedSleep(5 * 3600, by: -1) == 5 * 3600)
        #expect(OnboardingGoalSteps.steppedLifts(7, by: 1) == 7)
        #expect(OnboardingGoalSteps.steppedLifts(0, by: -1) == 0)
        #expect(OnboardingGoalSteps.steppedDistance(meters: 25_000, by: 1, formatter: metric) == 30_000)
        #expect(OnboardingGoalSteps.steppedDistance(meters: 0, by: -1, formatter: metric) == 0)
        // 25 km shows as 16 mi; stepping up lands on 20 mi, down on 15 mi.
        let up = imperial.displayDistance(meters: OnboardingGoalSteps.steppedDistance(meters: 25_000, by: 1, formatter: imperial))
        let down = imperial.displayDistance(meters: OnboardingGoalSteps.steppedDistance(meters: 25_000, by: -1, formatter: imperial))
        #expect(abs(up - 20) < 0.001)
        #expect(abs(down - 15) < 0.001)
    }

    @Test func dateOfBirthKeepsExistingWhenAgeMatches() {
        let calendar = TestSupport.utc
        let now = TestSupport.referenceDate
        let existing = calendar.date(from: DateComponents(year: 2005, month: 3, day: 14))!
        #expect(AboutYouModel.dateOfBirth(forAge: 21, existing: existing, now: now, calendar: calendar) == existing)
        let changed = AboutYouModel.dateOfBirth(forAge: 30, existing: existing, now: now, calendar: calendar)
        #expect(calendar.dateComponents([.year], from: changed, to: now).year == 30)
    }

    @Test func decimalParsingAcceptsCommas() {
        #expect(AboutYouModel.parseDecimal("78,4") == 78.4)
        #expect(AboutYouModel.parseDecimal("abc") == nil)
    }

    @Test func unitsChangeReformatsWeightImmediately() async {
        let container = AppContainer.preview(.standard, onboarded: false)
        let model = AboutYouModel(repository: container.repository)
        await model.prefillFromHealth()
        #expect(model.bodyMassKilograms != nil)
        let metricText = model.weightText
        model.setUnits(.imperial)
        #expect(model.weightText != metricText)
        #expect(container.settings.settings.units == .imperial)
        // Re-expressing the weight must not turn the Health value into a manual edit.
        #expect(model.isFromHealth)
    }

    @Test func prefillFillsProfileOnce() async {
        let container = AppContainer.preview(.standard, onboarded: false)
        let model = AboutYouModel(repository: container.repository)
        await model.prefillFromHealth()
        #expect(model.sex == .male)
        #expect(model.ageText == "21")
        #expect(model.maxHeartRate == 193)
        model.setSex(.female)
        await model.prefillFromHealth()
        #expect(model.sex == .female)
    }

    @Test func deniedScenarioNavigatesToDeniedState() async {
        let container = AppContainer.preview(.healthAccessDenied, onboarded: false)
        let model = OnboardingModel()
        model.push(.healthAccess)
        await model.requestHealthAccess(in: container)
        #expect(model.path.last == .healthDenied)
    }

    @Test func importCompletesOnboarding() async {
        let container = AppContainer.preview(.newUser, onboarded: false)
        let model = OnboardingModel()
        model.startImport(in: container)
        for _ in 0..<200 where !model.isImportFinished { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(model.isImportFinished)
        model.complete(in: container)
        #expect(container.settings.settings.onboarding.completed)
    }
}

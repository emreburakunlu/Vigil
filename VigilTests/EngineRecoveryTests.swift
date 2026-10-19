import Foundation
import Testing
@testable import Vigil

@Suite("Engine · Recovery")
struct EngineRecoveryTests {
    let engine = EngineFixtures.engine

    func recovery(hrv: Double? = 61, rhr: Double? = 55, rr: Double? = 14.6, temp: Double? = 36.4, sleep: Int? = 75,
                  baselines: PersonalBaselines = EngineFixtures.baselines(), previousDayStrain: DailyStrain? = nil,
                  trainingLoad: TrainingLoad? = nil) -> RecoveryScore {
        engine.recovery(EngineFixtures.recoveryInput(vitals: EngineFixtures.vitals(hrv: hrv, rhr: rhr, rr: rr, temp: temp), sleep: sleep,
                                                     baselines: baselines, previousDayStrain: previousDayStrain, trainingLoad: trainingLoad))
    }

    func points(_ kind: RecoveryFactorKind, _ r: RecoveryScore) -> Int { r.factors.first { $0.kind == kind }?.points ?? .min }

    @Test func everythingAtBaselineIsNeutral() {
        let r = recovery()
        #expect(r.value == DefaultScoreEngine.Recovery.neutral)
        #expect(r.factors.allSatisfy { $0.points == 0 })
        #expect(r.band == .yellow)
        #expect(r.suggestion == .maintain)
        #expect(r.signalsUsed == 5 && !r.isPartial && !r.isCalibrating)
        #expect(r.message == "Your signals are close to your baseline. Keep it steady today.")
    }

    @Test(arguments: [
        (61.0, 55.0, 14.6, 36.4, 75), (80, 50, 14.6, 36.4, 90), (40, 62, 16, 37.1, 40), (68, 52, 14.6, 36.61, 84),
        (55, 57, 15.5, 36.2, 60), (120, 45, 14.6, 36.4, 100), (25, 75, 19, 38, 10),
    ])
    func pointsSumToValue(hrv: Double, rhr: Double, rr: Double, temp: Double, sleep: Int) {
        let r = recovery(hrv: hrv, rhr: rhr, rr: rr, temp: temp, sleep: sleep)
        #expect(DefaultScoreEngine.Recovery.neutral + r.factors.reduce(0) { $0 + $1.points } == r.value)
        #expect((0...100).contains(r.value))
        #expect(r.band == RecoveryBand(percent: r.value))
    }

    @Test func higherHRVNeverLowersRecovery() {
        let values = stride(from: 30.0, through: 120, by: 5).map { recovery(hrv: $0).value }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.first! < 40 && values.last! > 75)
    }

    @Test func higherRestingHRLowersRecovery() {
        let values = stride(from: 45.0, through: 70, by: 1).map { recovery(rhr: $0).value }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(values.first! > values.last!)
    }

    @Test func betterSleepRaisesRecovery() {
        let values = stride(from: 0, through: 100, by: 10).map { recovery(sleep: $0).value }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(points(.sleep, recovery(sleep: 95)) > 0)
        #expect(points(.sleep, recovery(sleep: 50)) < 0)
    }

    @Test func respiratoryAndTemperatureOnlyPenaliseLargeDeviations() {
        #expect(points(.respiratoryRate, recovery(rr: 14.9)) == 0) // within 1 SD
        #expect(points(.wristTemperature, recovery(temp: 36.5)) == 0) // within the 0.15 °C floor
        #expect(points(.respiratoryRate, recovery(rr: 16.4)) < 0)
        #expect(points(.respiratoryRate, recovery(rr: 12.8)) < 0) // deviation either way
        #expect(points(.wristTemperature, recovery(temp: 37.0)) < 0)
        #expect(recovery(temp: 37.0).value < recovery().value)
    }

    @Test func bandsAndSuggestions() {
        let green = recovery(hrv: 85, rhr: 50, sleep: 92)
        #expect(green.value >= 67 && green.band == .green && green.suggestion == .push)
        #expect(green.message.hasSuffix("Good day for intervals."))
        let red = recovery(hrv: 35, rhr: 63, sleep: 45)
        #expect(red.value <= 33 && red.band == .red && red.suggestion == .takeItEasy)
        #expect(red.message.hasSuffix("Keep it light today."))
        #expect(RecoveryBand(percent: 67) == .green && RecoveryBand(percent: 66) == .yellow)
        #expect(RecoveryBand(percent: 34) == .yellow && RecoveryBand(percent: 33) == .red)
    }

    @Test func messageLeadsWithDominantSignal() {
        let r = recovery(hrv: 61 * 1.12)
        #expect(r.message == "HRV 12% above your baseline. Good day for intervals.")
        let rhr = recovery(rhr: 60)
        #expect(rhr.message.hasPrefix("Resting heart rate 5 bpm above your baseline."))
    }

    @Test func suggestedStrainFollowsRecovery() {
        let r = recovery(hrv: 61 * 1.12)
        let expectedLow = Int((0.6 * Double(r.value) + 8).rounded())
        #expect(r.suggestedStrain == expectedLow...Int((0.6 * Double(r.value) + 28).rounded()))
        #expect(recovery(hrv: 30).suggestedStrain.upperBound < r.suggestedStrain.lowerBound + 20)
    }

    @Test func highTrainingLoadDowngradesPush() {
        let today = EngineFixtures.today
        let spike = TrainingLoad(day: today, acute: 160, chronic: 100, ratio: 1.6, risk: .high, history: [])
        let base = recovery(hrv: 85, rhr: 50, sleep: 92)
        let loaded = recovery(hrv: 85, rhr: 50, sleep: 92, trainingLoad: spike)
        #expect(base.suggestion == .push)
        #expect(loaded.suggestion == .maintain)
        #expect(loaded.value == base.value) // the score itself is unchanged
        #expect(loaded.suggestedStrain.upperBound == base.suggestedStrain.upperBound - 10)
        #expect(loaded.message.contains("Training load is high"))

        let allOut = DailyStrain(day: EngineFixtures.day(-1), value: 95, level: .allOut, workouts: [], everydayMovement: 0,
                                 zoneDurations: ZoneDurations(), trainingLoad: 400)
        #expect(recovery(hrv: 85, rhr: 50, sleep: 92, previousDayStrain: allOut).suggestion == .maintain)
    }

    @Test func partialSignals() {
        let r = recovery(rr: nil, temp: nil)
        #expect(r.signalsUsed == 3 && r.signalsTotal == 5 && r.isPartial)
        #expect(r.factors.filter { !$0.isAvailable }.allSatisfy { $0.points == 0 })
        let sleepOnly = engine.recovery(EngineFixtures.recoveryInput(vitals: nil, sleep: 90))
        #expect(sleepOnly.signalsUsed == 1)
        #expect(sleepOnly.value > DefaultScoreEngine.Recovery.neutral)
    }

    @Test func calibratingWithLittleHistory() {
        let r = recovery(hrv: 90, rhr: 48, sleep: 80, baselines: EngineFixtures.baselines(count: 3))
        #expect(r.isCalibrating)
        #expect(r.calibrationDaysRemaining == 4)
        #expect(r.factors.first { $0.kind == .heartRateVariability }?.isAvailable == false)
        #expect(r.message.hasPrefix("Still learning your baselines: 4 more nights needed."))
        let none = recovery(baselines: PersonalBaselines(day: EngineFixtures.today))
        #expect(none.calibrationDaysRemaining == 7)
        #expect(recovery().calibrationDaysRemaining == nil)
    }

    @Test func apportionKeepsTotal() {
        #expect(EngineMath.apportion([1.2, 2.7, 3.5], total: 8, eligible: [true, true, true]) == [1, 3, 4])
        #expect(EngineMath.apportion([-1.2, -2.7], total: -4, eligible: [true, true]) == [-1, -3])
        #expect(EngineMath.apportion([0, 0], total: 0, eligible: [false, false]) == [0, 0])
    }
}

import SwiftUI

// Building blocks for workouts logged in Vigil (`LiftLogStore`): set formatting, the
// Start / Resume button and the "Logged workouts" row.

extension VigilFormatter {
    /// Set weight in the user's unit without trailing zeros: `"60 kg"`, `"62.5 kg"`, `"135 lb"`.
    func setWeight(kilograms: Double) -> FormattedValue {
        let display = displayWeight(kilograms: kilograms)
        let digits = abs(display - display.rounded()) < 0.05 ? 0 : 1
        return weight(kilograms: kilograms, fractionDigits: digits)
    }

    /// `"60 × 8"` (display unit, no unit label) for the "Previous" column.
    func setSummary(_ set: LoggedSet) -> String {
        "\(setWeight(kilograms: set.weightKilograms).value) × \(set.reps)"
    }

    /// Text for an editable weight field in the user's unit (empty for zero).
    func weightFieldText(kilograms: Double) -> String {
        guard kilograms > 0 else { return "" }
        return displayWeight(kilograms: kilograms)
            .formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    /// Parses a weight field (either decimal separator) back to kilograms; empty is zero.
    func kilograms(fromWeightFieldText text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return nil }
        return kilograms(fromDisplayWeight: value)
    }
}

enum LiftLogFormatting {
    /// Default session title from the time of day.
    static func defaultTitle(at date: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: String(localized: "Morning lift")
        case 12..<17: String(localized: "Afternoon lift")
        default: String(localized: "Evening lift")
        }
    }
}

/// "Start workout", or "Resume workout · 12:34" while a session is active.
struct LiftLogStartButton: View {
    let onStart: () -> Void
    let onResume: (LiftSession) -> Void
    @Environment(LiftLogStore.self) private var liftLog
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        if let active = liftLog.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = settingsStore.formatter.duration(active.duration(at: context.date), style: .clock)
                PrimaryButton("Resume workout · \(elapsed)", systemImage: "play.fill") { onResume(active) }
            }
        } else {
            PrimaryButton("Start workout", systemImage: "plus") { onStart() }
        }
    }
}

/// One workout logged in Vigil, in the Train · Lift list.
struct LoggedLiftRow: View {
    let session: LiftSession
    let model: TrainModel
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let formatter = settingsStore.formatter
        let date = TrainFormatting.rowDate(session.start, style: .lift, now: model.now, calendar: model.calendar, formatter: formatter)
        let volume = formatter.weight(kilograms: session.totalVolumeKilograms, fractionDigits: 0)
        let duration = formatter.duration(session.duration(), style: .minutes)
        VStack(spacing: VSpacing.l) {
            HStack(spacing: VSpacing.l) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.vStrainInk)
                    .frame(width: 42, height: 42)
                    .background(Color.vLiftTint, in: .rect(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.title).vTextStyle(.body).fontWeight(.bold).foregroundStyle(Color.vInk).lineLimit(1)
                    Text("\(date) · ^[\(session.exercises.count) exercise](inflect: true)")
                        .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary).lineLimit(1)
                }
                Spacer(minLength: VSpacing.xs)
                VChip("Vigil", tone: .lift)
            }
            Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline)
            HStack(alignment: .top) {
                TrainLiftMetric(value: duration, label: String(localized: "duration"))
                TrainLiftMetric(value: "\(session.completedSetCount)", label: String(localized: "sets"))
                TrainLiftMetric(value: volume.value, label: String(localized: "\(volume.unit) volume"))
            }
        }
        .padding(.horizontal, VSpacing.xxl)
        .padding(.vertical, VSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
        .shadow(color: .vShadow, radius: 1, y: 1)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.title), \(date), logged in Vigil")
        .accessibilityValue("\(duration), \(session.completedSetCount) sets, \(volume.text) volume")
        .accessibilityAddTraits(.isButton)
    }
}

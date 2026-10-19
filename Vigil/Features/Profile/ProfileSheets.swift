import SwiftUI

/// Which editor sheet Profile is showing.
enum ProfileSheet: String, Identifiable {
    case age, sex, weight, maxHeartRate, sleepGoal, runGoal, liftGoal, privacy, export, reimport
    var id: String { rawValue }
}

// MARK: - Profile editors

struct ProfileAgeSheet: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ProfileSheetScaffold(title: "Date of birth") {
            DatePicker("Date of birth", selection: Binding(
                get: { settingsStore.settings.profile.dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now },
                set: { value in settingsStore.update { $0.profile.dateOfBirth = value } }),
                       in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Text("Used to estimate your maximum heart rate. It never leaves this iPhone.")
                .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
        }
    }
}

struct ProfileSexSheet: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ProfileSheetScaffold(title: "Sex", detents: [.height(260)]) {
            VSegmentedControl(selection: Binding(
                get: { settingsStore.settings.profile.sex ?? .other },
                set: { value in settingsStore.update { $0.profile.sex = value } }),
                              options: BiologicalSex.allCases) { Self.title($0) }
            Text("Used only for heart-rate and calorie estimates.")
                .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
        }
    }

    static func title(_ sex: BiologicalSex) -> LocalizedStringKey {
        switch sex {
        case .female: "Female"
        case .male: "Male"
        case .other: "Other"
        }
    }
}

struct ProfileWeightSheet: View {
    let healthBodyMass: Double?
    @Environment(SettingsStore.self) private var settingsStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let formatter = settingsStore.formatter
        ProfileSheetScaffold(title: "Body weight") {
            Toggle("Sync from Apple Health", isOn: Binding(
                get: { settingsStore.settings.profile.bodyMassFromHealth },
                set: { on in
                    settingsStore.update {
                        $0.profile.bodyMassFromHealth = on
                        if on, let healthBodyMass { $0.profile.bodyMassKilograms = healthBodyMass }
                    }
                }))
                .tint(.vPositive)
                .vTextStyle(.body)
            if !settingsStore.settings.profile.bodyMassFromHealth {
                HStack {
                    TextField("Weight", text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .vTextStyle(.title)
                        .onChange(of: text) { _, newValue in commit(newValue, formatter: formatter) }
                    Text(formatter.weightUnit).vTextStyle(.body).foregroundStyle(Color.vInkSecondary)
                }
                .padding(VSpacing.xl)
                .background(Color.vFill, in: .rect(cornerRadius: VRadius.chip, style: .continuous))
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
                }
            }
        }
        .onAppear {
            if let kg = settingsStore.settings.profile.bodyMassKilograms {
                text = formatter.number(formatter.displayWeight(kilograms: kg), fractionDigits: 1)
            }
        }
    }

    private func commit(_ text: String, formatter: VigilFormatter) {
        guard let value = try? Double(text, format: .number), value.isFinite else { return }
        let kilograms = formatter.kilograms(fromDisplayWeight: value)
        guard ProfileLogic.isPlausibleBodyMass(kilograms: kilograms) else { return }
        settingsStore.update { $0.profile.bodyMassKilograms = kilograms }
    }
}

struct ProfileMaxHeartRateSheet: View {
    let estimated: Int
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let profile = settingsStore.settings.profile
        ProfileSheetScaffold(title: "Max heart rate") {
            VSegmentedControl(selection: Binding(
                get: { settingsStore.settings.profile.estimatesMaxHeartRate },
                set: { auto in
                    settingsStore.update {
                        $0.profile.estimatesMaxHeartRate = auto
                        if !auto, $0.profile.manualMaxHeartRate == nil { $0.profile.manualMaxHeartRate = estimated }
                    }
                }),
                              options: [true, false]) { $0 ? "Automatic" : "Manual" }
            if profile.estimatesMaxHeartRate {
                Text("Estimated from your age: \(estimated) bpm. Vigil raises it if you go higher in a workout.")
                    .vTextStyle(.callout).foregroundStyle(Color.vInkSecondary)
            } else {
                Stepper(value: Binding(
                    get: { settingsStore.settings.profile.manualMaxHeartRate ?? estimated },
                    set: { value in settingsStore.update { $0.profile.manualMaxHeartRate = value } }),
                        in: ProfileLogic.maxHeartRateRange) {
                    Text("\(profile.manualMaxHeartRate ?? estimated) bpm").vTextStyle(.title)
                }
                Text("Estimated for you: \(estimated) bpm.").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
            }
        }
    }
}

// MARK: - Goals

struct ProfileSleepGoalSheet: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ProfileSheetScaffold(title: "Nightly sleep", detents: [.height(260)]) {
            Stepper(value: Binding(
                get: { settingsStore.settings.goals.sleepTarget },
                set: { value in settingsStore.update { $0.goals.sleepTarget = ProfileLogic.clampedSleepTarget(value) } }),
                    in: ProfileLogic.sleepTargetRange, step: ProfileLogic.sleepTargetStep) {
                Text(VigilFormatter.duration(settingsStore.settings.goals.sleepTarget)).vTextStyle(.title)
            }
            Text("Between 5 and 11 hours, in 15-minute steps.").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
        }
    }
}

struct ProfileRunGoalSheet: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let formatter = settingsStore.formatter
        ProfileSheetScaffold(title: "Weekly running", detents: [.height(260)]) {
            Stepper(value: Binding(
                get: { formatter.displayDistance(meters: settingsStore.settings.goals.weeklyRunDistanceMeters).rounded() },
                set: { value in settingsStore.update { $0.goals.weeklyRunDistanceMeters = formatter.meters(fromDisplayDistance: value) } }),
                    in: 1...300, step: 1) {
                Text(formatter.distance(meters: settingsStore.settings.goals.weeklyRunDistanceMeters, fractionDigits: 0).text)
                    .vTextStyle(.title)
            }
            Text("Distance you want to run each week.").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
        }
    }
}

struct ProfileLiftGoalSheet: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ProfileSheetScaffold(title: "Weekly lifting", detents: [.height(260)]) {
            Stepper(value: settingsStore.binding(\.goals.weeklyLiftSessions), in: ProfileLogic.liftGoalRange) {
                Text("^[\(settingsStore.settings.goals.weeklyLiftSessions) session](inflect: true)").vTextStyle(.title)
            }
            Text("Strength sessions you want each week.").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
        }
    }
}

// MARK: - Privacy

struct ProfilePrivacySheet: View {
    var body: some View {
        ProfileSheetScaffold(title: "Privacy statement", detents: [.large]) {
            ForEach(Self.paragraphs.indices, id: \.self) { index in
                let (title, text) = Self.paragraphs[index]
                VStack(alignment: .leading, spacing: VSpacing.xs) {
                    Text(title).vTextStyle(.headline).foregroundStyle(Color.vInk)
                    Text(text).vTextStyle(.body).foregroundStyle(Color.vInkLabel)
                }
            }
        }
    }

    static let paragraphs: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Everything stays on this iPhone", "Vigil has no account, no servers and no analytics. Your scores, baselines and settings are stored only in the app's private storage on this device."),
        ("Apple Health is read-only", "Vigil reads the Health data you allow, such as sleep, heart rate, HRV and workouts, to calculate Recovery, Sleep and Strain. It never writes anything to Apple Health."),
        ("Notifications are local", "Morning summaries and bedtime reminders are scheduled on this device. No push notifications are used."),
        ("You are in control", "You can export your data, re-import it from Apple Health or delete everything Vigil stored at any time from Profile. Deleting does not touch Apple Health."),
    ]
}

// MARK: - Export

struct ProfileExportSheet: View {
    let model: ProfileModel
    @Environment(AppContainer.self) private var container

    var body: some View {
        ProfileSheetScaffold(title: "Export all data", detents: [.height(380)]) {
            switch model.export {
            case .idle, .preparing:
                HStack(spacing: VSpacing.l) {
                    ProgressView()
                    Text("Preparing your files…").vTextStyle(.body).foregroundStyle(Color.vInkSecondary)
                }
            case .failed:
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Export failed",
                               message: "Vigil couldn't build your files.", actionTitle: "Try again") {
                    Task { await model.prepareExport(container: container) }
                }
            case .ready(let files, let days, let workouts):
                Text("\(days) days of scores and \(workouts) workouts, in metric units.")
                    .vTextStyle(.callout).foregroundStyle(Color.vInkSecondary)
                ShareLink(items: [files.dailyCSV, files.workoutsCSV]) {
                    Label("Share CSV", systemImage: "tablecells").frame(maxWidth: .infinity)
                }
                .buttonStyle(.vPill(.primary))
                ShareLink(item: files.json) {
                    Label("Share JSON", systemImage: "curlybraces").frame(maxWidth: .infinity)
                }
                .buttonStyle(.vPill(.secondary))
            }
        }
        .task { await model.prepareExport(container: container) }
    }
}

// MARK: - Re-import

struct ProfileReimportSheet: View {
    let model: ProfileModel
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let progress = model.importProgress
        let finished = progress?.phase == .finished
        ProfileSheetScaffold(title: "Re-import history", detents: [.height(320)]) {
            if model.importFailed {
                Text("The import didn't finish. Check Apple Health access and try again.")
                    .vTextStyle(.body).foregroundStyle(Color.vDangerInk)
                PrimaryButton("Try again") { Task { await model.reimport(container: container) } }
            } else {
                ProgressView(value: progress?.fraction ?? 0).tint(.vAccent)
                    .accessibilityLabel("Import progress")
                    .accessibilityValue("\(Int((progress?.fraction ?? 0) * 100)) percent")
                Text(subtitle(progress)).vTextStyle(.callout).foregroundStyle(Color.vInkSecondary)
                if finished { PrimaryButton("Done") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(progress != nil && !finished && !model.importFailed)
        .task { await model.reimport(container: container) }
    }

    private func subtitle(_ progress: ImportProgress?) -> LocalizedStringKey {
        guard let progress else { return "Starting…" }
        if progress.phase == .finished { return "Done. \(progress.nightsImported) nights and \(progress.workoutsImported) workouts imported." }
        return "\(Int(progress.fraction * 100))% · \(progress.nightsImported) nights · \(progress.workoutsImported) of \(progress.workoutsTotal) workouts"
    }
}

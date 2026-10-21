import SwiftUI

/// Full-screen logger for the active lifting session: title, live timer, exercises with their sets.
/// Edits live in local state (keeps typing responsive) and are written through to
/// `LiftLogStore.updateActive` on every change. Minimizing keeps the session active.
struct ActiveWorkoutView: View {
    /// Called with the session id after a successful finish (the store may have dropped an empty one).
    let onFinish: (UUID) -> Void
    @Environment(LiftLogStore.self) private var liftLog
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var session: LiftSession
    @State private var isAddingExercise = false
    @State private var prompt: Prompt?
    /// Set once finishing/discarding so late edits don't resurrect the session.
    @State private var isClosing = false

    init(session: LiftSession, onFinish: @escaping (UUID) -> Void = { _ in }) {
        _session = State(initialValue: session)
        self.onFinish = onFinish
    }

    private enum Prompt: Identifiable {
        case incompleteSets, nothingCompleted, discard
        var id: Self { self }
    }

    var body: some View {
        let formatter = settingsStore.formatter
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                    header(formatter)
                    ForEach($session.exercises) { $exercise in
                        ActiveWorkoutExerciseCard(exercise: $exercise, last: liftLog.lastPerformance(of: exercise.name),
                                                  formatter: formatter) {
                            let id = exercise.id
                            withAnimation(VMotion.ease(duration: 0.2)) { session.exercises.removeAll { $0.id == id } }
                        }
                    }
                    if session.exercises.isEmpty {
                        EmptyStateView(systemImage: "dumbbell", title: "No exercises yet",
                                       message: "Add a movement, then log each set's weight and reps.")
                            .vCard()
                    }
                    SecondaryButton("Add exercise", systemImage: "plus") { isAddingExercise = true }
                }
                .padding(.horizontal, VSpacing.screenGutter)
                .padding(.top, VSpacing.s)
                .padding(.bottom, VSpacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.vBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $isAddingExercise) {
            ActiveWorkoutExercisePicker(recent: liftLog.recentExerciseNames) { addExercise(named: $0) }
        }
        .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { prompt in
            switch prompt {
            case .incompleteSets:
                Button("Finish") { finish() }
                Button("Keep logging", role: .cancel) {}
            case .nothingCompleted, .discard:
                Button("Discard workout", role: .destructive) { discard() }
                Button("Keep logging", role: .cancel) {}
            }
        } message: { prompt in
            switch prompt {
            case .incompleteSets: Text("Sets you haven't checked off won't be saved.")
            case .nothingCompleted: Text("No sets are checked off, so there's nothing to save.")
            case .discard: Text("This workout and its sets will be deleted.")
            }
        }
        .onChange(of: session) { _, updated in
            guard !isClosing else { return }
            liftLog.updateActive { $0 = updated }
        }
    }

    private var promptTitle: LocalizedStringKey {
        switch prompt {
        case .incompleteSets: "Finish workout?"
        case .nothingCompleted: "Discard workout?"
        case .discard: "Discard workout?"
        case nil: ""
        }
    }

    // MARK: Sections

    private func header(_ formatter: VigilFormatter) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            TextField("Workout name", text: $session.title)
                .vTextStyle(.largeTitle)
                .foregroundStyle(Color.vInk)
                .submitLabel(.done)
                .accessibilityLabel("Workout name")
            HStack(spacing: VSpacing.m) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TrainTile(label: "Elapsed", value: formatter.duration(session.duration(at: context.date), style: .clock))
                }
                TrainTile(label: "Sets", value: "\(session.completedSetCount)")
                let volume = formatter.weight(kilograms: session.totalVolumeKilograms, fractionDigits: 0)
                TrainTile(label: "Volume", value: volume.value, unit: volume.unit)
            }
        }
        .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Minimize workout")
        }
        ToolbarItem(placement: .principal) {
            Text("Workout").vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Discard workout", systemImage: "trash", role: .destructive) { prompt = .discard }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") { finishTapped() }
                .fontWeight(.bold)
                .tint(Color.vLift)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { endEditing() }
        }
    }

    // MARK: Actions

    private func addExercise(named name: String) {
        let first = liftLog.lastPerformance(of: name)?.completedSets.first
        let set = LoggedSet(reps: first?.reps ?? 0, weightKilograms: first?.weightKilograms ?? 0)
        session.exercises.append(LoggedExercise(name: name, sets: [set]))
    }

    private func finishTapped() {
        endEditing()
        if session.completedSetCount == 0 {
            prompt = .nothingCompleted
        } else if session.exercises.contains(where: { $0.sets.contains { !$0.isCompleted } }) {
            prompt = .incompleteSets
        } else {
            finish()
        }
    }

    /// Keeps only checked-off sets (and exercises that have any), then ends the session.
    private func finish() {
        var final = session
        final.exercises = final.exercises.compactMap { exercise in
            var exercise = exercise
            exercise.sets = exercise.completedSets
            return exercise.sets.isEmpty ? nil : exercise
        }
        let title = final.title.trimmingCharacters(in: .whitespacesAndNewlines)
        final.title = title.isEmpty ? LiftLogFormatting.defaultTitle(at: final.start) : title
        isClosing = true
        liftLog.updateActive { $0 = final }
        liftLog.finishActive()
        dismiss()
        onFinish(final.id)
    }

    private func discard() {
        isClosing = true
        dismiss()
        liftLog.discardActive()
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// One exercise: name + menu, column headers, set rows and "Add set".
struct ActiveWorkoutExerciseCard: View {
    @Binding var exercise: LoggedExercise
    /// The last finished session's performance of this movement, for "Previous" and prefills.
    let last: LoggedExercise?
    let formatter: VigilFormatter
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: exercise.name).vTextStyle(.headline).foregroundStyle(Color.vLift)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: VSpacing.s)
                Menu {
                    if !exercise.sets.isEmpty {
                        Button("Delete last set", systemImage: "minus.circle") { exercise.sets.removeLast() }
                    }
                    Button("Remove exercise", systemImage: "trash", role: .destructive) { onRemove() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.vInkSecondary)
                        .frame(width: VSize.minTapTarget, height: VSize.minTapTarget)
                        .contentShape(.rect)
                }
                .accessibilityLabel("\(exercise.name) options")
            }
            ActiveWorkoutSetColumns {
                Text("Set")
                Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: formatter.weightUnit)
                Text("Reps")
                Image(systemName: "checkmark").accessibilityLabel("Done")
            }
            .font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(Color.vInkSecondary)
            ForEach($exercise.sets) { $set in
                let index = exercise.sets.firstIndex { $0.id == set.id } ?? 0
                ActiveWorkoutSetRow(number: index + 1, set: $set, previous: previous(at: index), formatter: formatter) {
                    let id = set.id
                    withAnimation(VMotion.ease(duration: 0.2)) { exercise.sets.removeAll { $0.id == id } }
                }
            }
            Button {
                addSet()
            } label: {
                Label("Add set", systemImage: "plus")
                    .vTextStyle(.bodyStrong)
                    .foregroundStyle(Color.vInk)
                    .frame(maxWidth: .infinity, minHeight: VSize.minTapTarget)
                    .background(Color.vFill, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
            }
            .buttonStyle(.vPress)
        }
        .vCard()
    }

    private func previous(at index: Int) -> LoggedSet? {
        guard let sets = last?.completedSets, !sets.isEmpty else { return nil }
        return index < sets.count ? sets[index] : nil
    }

    /// Copies the previous set in this exercise, else the matching set from last time.
    private func addSet() {
        let template = exercise.sets.last ?? previous(at: exercise.sets.count) ?? last?.completedSets.last
        exercise.sets.append(LoggedSet(reps: template?.reps ?? 0, weightKilograms: template?.weightKilograms ?? 0))
    }
}

/// Shared column layout so the header lines up with the set rows.
private struct ActiveWorkoutSetColumns<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: VSpacing.s) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index].frame(width: Self.widths[index], alignment: index == 1 ? .leading : .center)
                }
            }
        }
    }

    /// Set, previous (flexible), weight, reps, done.
    private static var widths: [CGFloat?] { [28, nil, 72, 56, VSize.minTapTarget] }
}

/// One set: number, previous, weight and reps fields, complete toggle. Long-press to delete.
struct ActiveWorkoutSetRow: View {
    let number: Int
    @Binding var set: LoggedSet
    let previous: LoggedSet?
    let formatter: VigilFormatter
    let onDelete: () -> Void
    @State private var weightText: String
    @State private var repsText: String

    init(number: Int, set: Binding<LoggedSet>, previous: LoggedSet?, formatter: VigilFormatter, onDelete: @escaping () -> Void) {
        self.number = number
        _set = set
        self.previous = previous
        self.formatter = formatter
        self.onDelete = onDelete
        _weightText = State(initialValue: formatter.weightFieldText(kilograms: set.wrappedValue.weightKilograms))
        _repsText = State(initialValue: set.wrappedValue.reps > 0 ? "\(set.wrappedValue.reps)" : "")
    }

    var body: some View {
        ActiveWorkoutSetColumns {
            Text("\(number)").vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel)
            Button {
                guard let previous else { return }
                set.weightKilograms = previous.weightKilograms
                set.reps = previous.reps
            } label: {
                Text(previous.map(formatter.setSummary) ?? "–")
                    .vTextStyle(.callout).foregroundStyle(Color.vInkSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(previous == nil)
            .accessibilityLabel(previous.map { "Previous \(formatter.setWeight(kilograms: $0.weightKilograms).text) × \($0.reps)" } ?? "No previous set")
            .accessibilityHint(previous == nil ? "" : "Copies the previous weight and reps")
            field("0", text: $weightText, keyboard: .decimalPad)
                .accessibilityLabel("Set \(number) weight, \(formatter.weightUnit)")
            field("0", text: $repsText, keyboard: .numberPad)
                .accessibilityLabel("Set \(number) reps")
            Button {
                set.isCompleted.toggle()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(set.isCompleted ? Color.vInkOnAccent : Color.vInkTertiary)
                    .frame(width: 36, height: 36)
                    .background(set.isCompleted ? Color.vLift : Color.vFill, in: .rect(cornerRadius: 10, style: .continuous))
                    .frame(width: VSize.minTapTarget, height: VSize.minTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.vPress)
            .sensoryFeedback(.success, trigger: set.isCompleted) { _, new in new }
            .accessibilityLabel("Set \(number) done")
            .accessibilityAddTraits(set.isCompleted ? .isSelected : [])
        }
        .padding(.vertical, VSpacing.xxs)
        .background(set.isCompleted ? Color.vLiftTint : Color.clear, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
        .contextMenu {
            Button("Delete set", systemImage: "trash", role: .destructive) { onDelete() }
        }
        .onChange(of: weightText) { _, text in
            if let kilograms = formatter.kilograms(fromWeightFieldText: text) { set.weightKilograms = kilograms }
        }
        .onChange(of: repsText) { _, text in
            let digits = text.filter(\.isNumber)
            if digits != text { repsText = digits; return }
            set.reps = Int(digits) ?? 0
        }
        // Reflect outside changes (e.g. copying the previous set) without fighting the user's typing.
        .onChange(of: set.weightKilograms) { _, kilograms in
            let typed = formatter.kilograms(fromWeightFieldText: weightText) ?? -1
            if abs(typed - kilograms) > 0.0001 { weightText = formatter.weightFieldText(kilograms: kilograms) }
        }
        .onChange(of: set.reps) { _, reps in
            if (Int(repsText) ?? 0) != reps { repsText = reps > 0 ? "\(reps)" : "" }
        }
    }

    private func field(_ placeholder: LocalizedStringKey, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .vTextStyle(.bodyStrong)
            .foregroundStyle(Color.vInk)
            .frame(height: 36)
            .background(Color.vCardRaised, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
    }
}

#Preview {
    ActiveWorkoutView(session: LiftSession(title: "Evening lift", start: .now.addingTimeInterval(-1_520), exercises: [
        LoggedExercise(name: "Bench Press", sets: [
            LoggedSet(reps: 8, weightKilograms: 60, isCompleted: true),
            LoggedSet(reps: 8, weightKilograms: 62.5),
        ]),
    ]))
    .vigilPreview(navigation: false)
}

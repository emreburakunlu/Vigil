import SwiftUI

/// A workout logged in Vigil: summary (duration, sets, volume) and each exercise's completed sets.
struct LoggedLiftDetailView: View {
    let sessionID: UUID
    @Environment(LiftLogStore.self) private var liftLog
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            if let session = liftLog.session(id: sessionID) {
                LoggedLiftDetailContent(session: session, formatter: settingsStore.formatter, calendar: container.repository.calendar)
            } else {
                EmptyStateView(systemImage: "dumbbell", title: "Workout not found", message: "It may have been deleted.")
                    .vCard()
                    .padding(VSpacing.screenGutter)
            }
        }
        .background(Color.vBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if liftLog.session(id: sessionID) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete workout", systemImage: "trash") { isConfirmingDelete = true }
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                dismiss()
                liftLog.delete(id: sessionID)
            }
        } message: {
            Text("Its exercises and sets will be removed from Vigil.")
        }
    }
}

private struct LoggedLiftDetailContent: View {
    let session: LiftSession
    let formatter: VigilFormatter
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            summary.padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
            totals
            ForEach(session.exercises) { exercise in
                if !exercise.completedSets.isEmpty { exerciseCard(exercise) }
            }
        }
        .padding(.horizontal, VSpacing.screenGutter)
        .padding(.bottom, VSpacing.huge)
    }

    private var summary: some View {
        let day = session.start.formatted(Date.FormatStyle(calendar: calendar).weekday(.wide).month(.abbreviated).day())
        let end = session.end.map { " – \(formatter.timeOfDay($0, calendar: calendar))" } ?? ""
        return VStack(alignment: .leading, spacing: VSpacing.xs) {
            Text(verbatim: "\(day) · \(formatter.timeOfDay(session.start, calendar: calendar))\(end)")
                .vTextStyle(.subheadline).foregroundStyle(Color.vInkSecondary)
            Text(verbatim: session.title).vTextStyle(.largeTitle).foregroundStyle(Color.vInk).accessibilityAddTraits(.isHeader)
            VChip("Logged in Vigil", systemImage: "list.bullet.clipboard", tone: .lift).padding(.top, VSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totals: some View {
        let volume = formatter.weight(kilograms: session.totalVolumeKilograms, fractionDigits: 0)
        return VStack(spacing: VSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration").vTextStyle(.subheadline).foregroundStyle(Color.vInkSecondary)
                Spacer()
                Text(formatter.duration(session.duration(), style: .clock)).vTextStyle(.title).foregroundStyle(Color.vInk)
            }
            .padding(.horizontal, VSpacing.cardPadding)
            .padding(.vertical, VSpacing.xxl)
            .frame(maxWidth: .infinity)
            .vCard(padding: 0, radius: 22)
            .accessibilityElement(children: .combine)
            HStack(spacing: VSpacing.m) {
                TrainValueCell(label: "Exercises", value: "\(session.exercises.count)")
                    .vCard(padding: VSpacing.cardPaddingCompact, radius: 20)
                TrainValueCell(label: "Sets", value: "\(session.completedSetCount)")
                    .vCard(padding: VSpacing.cardPaddingCompact, radius: 20)
                TrainValueCell(label: "Volume", value: volume.value, unit: volume.unit)
                    .vCard(padding: VSpacing.cardPaddingCompact, radius: 20)
            }
        }
    }

    private func exerciseCard(_ exercise: LoggedExercise) -> some View {
        let sets = exercise.completedSets
        return VStack(alignment: .leading, spacing: VSpacing.m) {
            Text(verbatim: exercise.name).vTextStyle(.headline).foregroundStyle(Color.vInk).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(sets.indices, id: \.self) { index in
                    if index > 0 { Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline) }
                    setRow(number: index + 1, set: sets[index], isBest: sets[index].id == exercise.bestSet?.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }

    private func setRow(number: Int, set: LoggedSet, isBest: Bool) -> some View {
        let weight = formatter.setWeight(kilograms: set.weightKilograms)
        return HStack(spacing: VSpacing.l) {
            Text("\(number)").vTextStyle(.bodyStrong).foregroundStyle(Color.vInkSecondary).frame(width: 24, alignment: .leading)
            Text(verbatim: "\(weight.text) × \(set.reps)").vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
            Spacer(minLength: VSpacing.s)
            if isBest { VChip("Best set", tone: .lift) }
        }
        .frame(minHeight: VSize.minTapTarget)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LoggedLiftDetailView(sessionID: UUID()).vigilPreview()
}

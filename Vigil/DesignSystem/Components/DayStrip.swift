import SwiftUI

/// One day in a `DayStrip`.
struct DayStripItem: Identifiable, Hashable {
    let day: LocalDay
    /// Score dot colour under the number (`Color.vRecoveryBand(_)`); nil hides the dot.
    var dot: Color?
    /// Future days are disabled.
    var isEnabled = true
    /// Spoken after the date, e.g. "recovery 78 percent".
    var accessibilityValue: String?

    var id: LocalDay { day }
}

/// 7-day date strip (Today header): weekday, day number and a recovery-coloured dot per chip. The selected
/// chip is inverted (ink fill). Swiping left/right on the strip calls `onStep(+1/-1)` to move one day;
/// VoiceOver exposes the same through an adjustable action.
///
/// ```swift
/// DayStrip(items: items, selection: $day) { delta in day = day.adding(days: delta) }
/// ```
struct DayStrip: View {
    let items: [DayStripItem]
    @Binding var selection: LocalDay
    var calendar: Calendar = .current
    var onStep: ((Int) -> Void)?

    @Environment(\.vSurface) private var surface

    var body: some View {
        HStack(spacing: VSpacing.xxs) {
            ForEach(items) { item in
                chip(item)
            }
        }
        .contentShape(.rect)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > 48, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    onStep?(value.translation.width < 0 ? 1 : -1)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Days")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep?(1)
            case .decrement: onStep?(-1)
            @unknown default: break
            }
        }
    }

    private func chip(_ item: DayStripItem) -> some View {
        let isSelected = item.day == selection
        let date = item.day.startDate(in: calendar)
        return Button {
            selection = item.day
        } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(.current)))
                    .vTextStyle(.overline)
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(date.formatted(.dateTime.day()))
                    .font(.vCustom(.body, size: 17, weight: .bold, relativeTo: .headline))
                Circle()
                    .fill(item.dot ?? .clear)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(isSelected ? Color.vInkOnInverse : surface.ink)
            .frame(maxWidth: .infinity, minHeight: VSize.dayChipHeight)
            .background(isSelected ? Color.vInverseFill : .clear, in: .rect(cornerRadius: VRadius.dayChip, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.vPress)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.4)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(item.accessibilityValue ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DayStripPreview: View {
    @State var selection = LocalDay.today()
    var body: some View {
        let today = LocalDay.today()
        let items = (-6...0).map { offset in
            DayStripItem(day: today.adding(days: offset), dot: [Color.vRecovery, .vWarning, .vDanger, .vRecovery, .vRecovery, .vWarning, .vRecovery][offset + 6])
        }
        DayStrip(items: items, selection: $selection) { selection = selection.adding(days: $0) }
            .padding(.horizontal, 16)
            .padding(.vertical)
            .background(Color.vBackground)
    }
}

#Preview("DayStrip") { DayStripPreview() }

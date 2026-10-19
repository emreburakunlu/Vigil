import SwiftUI

/// Pill segmented control used for Run/Lift, Running/Lifting/Body, Push/Maintain/Take it easy and time ranges.
///
/// ```swift
/// VSegmentedControl(selection: $segment, options: TrainSegment.allCases) { $0 == .run ? "Run" : "Lift" }
/// VSegmentedControl(selection: $range, options: ranges, selectedFill: .vPositive, selectedInk: .vInkOnAccent) { … }
/// ```
/// Design: 4 pt track padding, 16 pt track radius, 40 pt segments with 12 pt radius, thumb shadow
/// `0 1px 3px rgba(18,20,26,.12)`. The thumb slides between segments (no animation with Reduce Motion).
struct VSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> LocalizedStringKey
    /// Optional coloured thumb (e.g. green "Push"); defaults to the neutral control thumb.
    var selectedFill: Color?
    var selectedInk: Color?
    var systemImage: ((Value) -> String?)?

    @Environment(\.vSurface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumbNamespace

    init(
        selection: Binding<Value>,
        options: [Value],
        selectedFill: Color? = nil,
        selectedInk: Color? = nil,
        systemImage: ((Value) -> String?)? = nil,
        title: @escaping (Value) -> LocalizedStringKey
    ) {
        _selection = selection
        self.options = options
        self.selectedFill = selectedFill
        self.selectedInk = selectedInk
        self.systemImage = systemImage
        self.title = title
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(VSpacing.xxs)
        .background(surface.controlTrack, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            if reduceMotion { selection = option } else {
                withAnimation(VMotion.ease(duration: 0.3)) { selection = option }
            }
        } label: {
            HStack(spacing: VSpacing.xs) {
                if let name = systemImage?(option) {
                    Image(systemName: name).font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                }
                Text(title(option))
                    .font(.vCustom(.body, size: 15, weight: isSelected ? .bold : .semibold, relativeTo: .callout))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? (selectedInk ?? surface.ink) : surface.inkLabel)
            .frame(maxWidth: .infinity, minHeight: VSize.segmentHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: VRadius.chip, style: .continuous)
                        .fill(selectedFill ?? surface.controlThumb)
                        .shadow(color: .vShadowStrong, radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SegmentedPreview: View {
    enum Seg: String, CaseIterable { case run = "Run", lift = "Lift" }
    enum Range: String, CaseIterable { case w = "W", m = "M", y = "Y", all = "All" }
    @State var seg = Seg.run
    @State var range = Range.m
    @State var advice = Range.w
    var body: some View {
        VStack(spacing: 16) {
            VSegmentedControl(selection: $seg, options: Seg.allCases) { LocalizedStringKey($0.rawValue) }
            VSegmentedControl(selection: $range, options: Range.allCases) { LocalizedStringKey($0.rawValue) }
            VSegmentedControl(selection: $advice, options: [.w, .m, .y], selectedFill: .vPositive, selectedInk: .vInkOnAccent) { LocalizedStringKey($0.rawValue) }
        }
        .padding()
        .background(Color.vBackground)
    }
}

#Preview("Segmented") { SegmentedPreview() }

import SwiftUI

/// Reload key for Progress segments: data reloads when the range changes, new data arrives
/// (`AppContainer.dataVersion`) or the day rolls over. Units are deliberately not part of it:
/// models keep canonical values and the views format them.
struct ProgressLoadKey: Hashable {
    var range: ProgressRange
    var dataVersion: Int
    var day: LocalDay

    /// Key for previews.
    static var preview: ProgressLoadKey { ProgressLoadKey(range: .threeMonths, dataVersion: 0, day: LocalDay(.now)) }
}

/// Card with a title row (title left, optional trailing note) and content.
struct ProgressCard<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: String?
    var trailingColor: Color = .vInkSecondary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).vTextStyle(.headline).foregroundStyle(Color.vInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: VSpacing.s)
                if let trailing {
                    Text(trailing).font(.vCustom(.body, size: 13.5, weight: .bold, relativeTo: .footnote))
                        .foregroundStyle(trailingColor)
                        .multilineTextAlignment(.trailing)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }
}

/// Big number with a small unit/caption beside it ("18.4 km avg / week").
struct ProgressBigValue: View {
    let value: String
    var caption: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: VSpacing.s) {
            Text(value).vTextStyle(.title).foregroundStyle(Color.vInk)
            if let caption {
                Text(caption).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

/// Three date captions under a chart (start, middle, end).
struct ProgressTicks: View {
    let dates: [Date]
    var format: Date.FormatStyle = .dateTime.month(.abbreviated).day()

    var body: some View {
        HStack {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                if index > 0 { Spacer(minLength: 0) }
                Text(date, format: format)
            }
        }
        .vTextStyle(.caption)
        .foregroundStyle(Color.vInkSecondary)
        .accessibilityHidden(true)
    }
}

/// 4W / 3M / 6M / 1Y pill row.
struct ProgressRangePicker: View {
    @Binding var selection: ProgressRange

    var body: some View {
        HStack(spacing: VSpacing.s) {
            ForEach(ProgressRange.allCases) { range in
                let isSelected = range == selection
                Button { selection = range } label: {
                    Text(range.rawValue)
                        .font(.vCustom(.body, size: 14, weight: .bold, relativeTo: .callout))
                        .foregroundStyle(isSelected ? Color.vInkOnInverse : Color.vInk)
                        .frame(maxWidth: .infinity, minHeight: VSize.minTapTarget - 6)
                        .background(isSelected ? Color.vInverseFill : Color.vCard, in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityLabel(Self.spokenName(range))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time range")
    }

    static func spokenName(_ range: ProgressRange) -> LocalizedStringKey {
        switch range {
        case .fourWeeks: "4 weeks"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        }
    }
}

/// Inline empty-state message inside a card.
struct ProgressMessage: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: VSpacing.l) {
            Image(systemName: systemImage).foregroundStyle(Color.vInkTertiary).accessibilityHidden(true)
            Text(text).vTextStyle(.callout).foregroundStyle(Color.vInkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

/// Shared scaffold for a segment: skeleton while loading, error card, otherwise the content.
/// Not a scroll view itself: `ProgressTabView` scrolls the header and the segment together.
struct ProgressSegmentScaffold<Content: View>: View {
    let phase: ProgressPhase
    let retry: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: VSpacing.xl) {
            switch phase {
            case .loading:
                VSkeletonStack(heights: [210, 300, 240])
            case .failed:
                VErrorCard(title: "Couldn't load progress", message: "Something went wrong reading your data.", retry: retry)
            case .loaded:
                content
            }
        }
    }
}

/// Spoken summary helper for chart accessibility values.
func progressSummary(_ points: [ProgressPoint], format: (Double) -> String) -> String {
    guard let first = points.first, let last = points.last else { return String(localized: "No data") }
    let low = points.map(\.value).min() ?? first.value
    let high = points.map(\.value).max() ?? first.value
    return String(localized: "From \(format(first.value)) to \(format(last.value)), low \(format(low)), high \(format(high))")
}

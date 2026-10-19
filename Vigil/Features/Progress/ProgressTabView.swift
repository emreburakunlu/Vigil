import SwiftUI

/// Tab 4 · Progress with Running / Lifting / Body (`AppRouter.progressSegment`).
/// Named `ProgressTabView` to avoid clashing with SwiftUI's `ProgressView`. Owner: Progress agent.
struct ProgressTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var range: ProgressRange = .threeMonths

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: VSpacing.l) {
                Text("Progress").vTextStyle(.largeTitle).foregroundStyle(Color.vInk)
                    .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
                    .accessibilityAddTraits(.isHeader)
                VSegmentedControl(selection: $router.progressSegment, options: ProgressSegment.allCases) {
                    switch $0 {
                    case .running: "Running"
                    case .lifting: "Lifting"
                    case .body: "Body"
                    }
                }
                ProgressRangePicker(selection: $range)
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.top, VSpacing.s)
            switch router.progressSegment {
            case .running: ProgressRunningView(range: range)
            case .lifting: ProgressLiftingView(range: range)
            case .body: ProgressBodyView(range: range)
            }
        }
        .background(Color.vBackground)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ProgressTabView().vigilPreview()
}

#Preview("Dark") {
    ProgressTabView().vigilPreview().preferredColorScheme(.dark)
}

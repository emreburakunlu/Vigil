import SwiftUI

/// Tab 4 · Progress with Running / Lifting / Body (`AppRouter.progressSegment`).
/// Named `ProgressTabView` to avoid clashing with SwiftUI's `ProgressView`. Owner: Progress agent.
struct ProgressTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppContainer.self) private var container
    @State private var range: ProgressRange = .threeMonths

    var body: some View {
        @Bindable var router = router
        let key = ProgressLoadKey(range: range, dataVersion: container.dataVersion, day: container.currentDay)
        // The title, segmented control and range chips scroll with the content (nothing floats over it).
        ScrollView {
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
                switch router.progressSegment {
                case .running: ProgressRunningView(key: key)
                case .lifting: ProgressLiftingView(key: key)
                case .body: ProgressBodyView(key: key)
                }
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.top, VSpacing.s)
            .padding(.bottom, VSpacing.xxxl)
        }
        .scrollIndicators(.hidden)
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

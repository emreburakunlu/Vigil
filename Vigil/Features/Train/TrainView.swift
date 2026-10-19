import SwiftUI

/// Tab 3 · Train with the Run / Lift switch (`AppRouter.trainSegment`, which survives while the app runs).
struct TrainView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppContainer.self) private var container
    @State private var model = TrainModel()

    var body: some View {
        @Bindable var router = router
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VSpacing.cardGap) {
                Text("Train")
                    .vTextStyle(.largeTitle)
                    .foregroundStyle(Color.vInk)
                    .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
                    .accessibilityAddTraits(.isHeader)
                VSegmentedControl(selection: $router.trainSegment, options: TrainSegment.allCases) { segment in
                    segment == .run ? "Run" : "Lift"
                }
                switch model.state {
                case .loading where model.weekly == nil:
                    TrainSkeletonStack()
                case .failed:
                    TrainErrorCard(title: "Couldn't load workouts", message: "Check that Vigil can read Health, then try again.") {
                        Task { await model.loadInitial(container.repository) }
                    }
                default:
                    switch router.trainSegment {
                    case .run: TrainRunView(model: model)
                    case .lift: TrainLiftView(model: model)
                    }
                }
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.top, VSpacing.s)
            .padding(.bottom, VSpacing.xxxl)
        }
        .background(Color.vBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadInitial(container.repository) }
    }
}

#Preview {
    TrainView().vigilPreview()
}

#Preview("No runs this week") {
    TrainView().vigilPreview(.noRunsThisWeek)
}

#Preview("No lifts this week") {
    TrainView().vigilPreview(.noLiftsThisWeek)
}

#Preview("Dark") {
    TrainView().vigilPreview().preferredColorScheme(.dark)
}

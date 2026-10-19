import SwiftUI

/// Progress · Body: Body weight, resting HR, HRV, recovery vs. load.
struct ProgressBodyView: View {
    var body: some View {
        ScreenPlaceholder(title: "Body", subtitle: "Body weight, resting HR, HRV, recovery vs. load") {}
    }
}

#Preview {
    ProgressBodyView().vigilPreview()
}

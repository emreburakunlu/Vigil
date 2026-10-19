import SwiftUI

/// Shared metric detail for any `HealthMetric` with D / W / M / 6M / Y ranges.
struct MetricDetailView: View {
    let metric: HealthMetric
    let day: LocalDay

    var body: some View {
        ScreenPlaceholder(title: metric.displayName, subtitle: day.isoString) {}
    }
}

#Preview {
    MetricDetailView(metric: .heartRateVariability, day: .today()).vigilPreview()
}

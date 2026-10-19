import SwiftUI

/// Onb7 · History import. Runs the 90-day import, then "Open Vigil" completes onboarding.
struct HistoryImportView: View {
    @Environment(AppContainer.self) private var container
    @State private var progress: ImportProgress?
    @State private var failed = false

    var body: some View {
        ScreenPlaceholder(title: "Reading your last 90 days", subtitle: subtitle) {
            if progress?.phase == .finished || failed {
                PlaceholderPrimaryButton("Open Vigil") {
                    container.settings.update { $0.onboarding.completed = true }
                }
            } else {
                ProgressView(value: progress?.fraction ?? 0)
                    .tint(.vAccent)
            }
        }
        .task {
            do {
                for try await event in container.importer.importHistory() { progress = event }
            } catch {
                failed = true
            }
        }
    }

    private var subtitle: String {
        guard let progress else { return "Starting…" }
        return "\(Int(progress.fraction * 100))% · \(progress.nightsImported) nights · \(progress.workoutsImported) of \(progress.workoutsTotal) workouts"
    }
}

#Preview {
    HistoryImportView().vigilPreview(onboarded: false)
}

import SwiftUI

/// "Add exercise" sheet: recently logged movements first, then the built-in catalog, plus a
/// custom "Add “…”" row for anything typed that isn't listed.
struct ActiveWorkoutExercisePicker: View {
    let recent: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ name: String) -> Bool {
        trimmedQuery.isEmpty || name.localizedStandardContains(trimmedQuery)
    }

    private var recentMatches: [String] { recent.filter(matches) }

    /// Catalog names not already shown under Recent.
    private var catalogMatches: [String] {
        let shown = Set(recent.map { $0.lowercased() })
        return ExerciseCatalog.common.filter { !shown.contains($0.lowercased()) && matches($0) }
    }

    /// The typed name when nothing listed matches it exactly.
    private var customName: String? {
        guard !trimmedQuery.isEmpty else { return nil }
        let exists = (recent + ExerciseCatalog.common).contains { $0.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
        return exists ? nil : trimmedQuery
    }

    var body: some View {
        NavigationStack {
            List {
                if let customName {
                    Section {
                        Button { pick(customName) } label: {
                            Label("Add “\(customName)”", systemImage: "plus.circle.fill")
                                .vTextStyle(.bodyStrong).foregroundStyle(Color.vLift)
                        }
                        .listRowBackground(Color.vCard)
                    }
                }
                if !recentMatches.isEmpty {
                    Section("Recent") { rows(recentMatches) }
                }
                if !catalogMatches.isEmpty {
                    Section("All exercises") { rows(catalogMatches) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search or type a name")
            .onSubmit(of: .search) { if let name = customName ?? (recentMatches + catalogMatches).first { pick(name) } }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func rows(_ names: [String]) -> some View {
        ForEach(names, id: \.self) { name in
            Button { pick(name) } label: {
                Text(verbatim: name).vTextStyle(.body).foregroundStyle(Color.vInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .listRowBackground(Color.vCard)
        }
    }

    private func pick(_ name: String) {
        onSelect(name)
        dismiss()
    }
}

#Preview {
    ActiveWorkoutExercisePicker(recent: ["Bench Press", "Cable Crunch"]) { _ in }
}

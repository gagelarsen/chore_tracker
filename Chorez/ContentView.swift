import SwiftData
import SwiftUI

/// Root screen placeholder.
///
/// PR2 replaces this with the real Home screen. For PR1 it stays the
/// welcome label (so the existing UI smoke test keeps passing) and adds
/// the single auto-fill hook the Phase 1 plan specifies: on first scene
/// appear of the day, generate today's `ChoreInstance` rows from active
/// templates. With no household or templates yet, the call is a no-op,
/// but the wiring is in place so PR2 only has to swap in the real view.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, Chorez")
                .font(.title2)
                .accessibilityIdentifier("welcomeLabel")
        }
        .padding()
        .task {
            // PR1: no UI to surface failures yet. PR2 routes this through
            // a proper error banner. `try?` is the right shape until then.
            try? ChoreRepository(context: modelContext)
                .autoFillTodayIfNeeded(now: .now)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ChorezSchema.allModels, inMemory: true)
}

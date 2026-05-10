import SwiftData
import SwiftUI

/// Application entry point.
///
/// Owns the live `ModelContainer`. PR2 will introduce a real
/// `AppEnvironment` to hold view-model wiring; for PR1 the container is
/// attached directly so repositories and tests share a single schema
/// source (`ChorezSchema.allModels`).
@main
struct ChorezApp: App {
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(ChorezSchema.allModels))
        } catch {
            // Failing to bring up the persistent store is unrecoverable;
            // there's no useful state to fall back to. Crash loudly so
            // it's caught in dev/CI rather than masked by a hollow UI.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

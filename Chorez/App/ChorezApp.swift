import SwiftData
import SwiftUI

/// Application entry point.
///
/// Owns the live `ModelContainer` and the `AppEnvironment` DI container.
/// Both are injected at the scene root so every view can resolve
/// repositories via `@Environment(AppEnvironment.self)` and SwiftData
/// types via `@Environment(\.modelContext)`.
@main
struct ChorezApp: App {
    private let container: ModelContainer
    private let appEnvironment: AppEnvironment

    init() {
        // UI tests launch the app with `-UITesting` so each run starts
        // against an in-memory store — flips to a clean slate without
        // having to uninstall the app between cases. Production launches
        // get the default on-disk store.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            let container = try ModelContainer(for: Schema(ChorezSchema.allModels),
                                               configurations: [configuration])
            self.container = container
            self.appEnvironment = AppEnvironment(context: container.mainContext)
        } catch {
            // Bringing up the persistent store is unrecoverable on the
            // hot path; crash loudly so it's caught in dev/CI rather
            // than masked by a hollow UI.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // PR1's auto-fill hook stays at the app level so it
                    // runs once per launch, before any screen renders.
                    // No-op until a household + active templates exist.
                    try? appEnvironment.chores.autoFillTodayIfNeeded(now: .now)
                }
        }
        .modelContainer(container)
        .environment(appEnvironment)
    }
}

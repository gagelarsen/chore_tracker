import SwiftUI

/// Application entry point.
///
/// Hosts the root SwiftUI scene. Domain wiring (state stores, dependency
/// injection) will land here as features are added.
@main
struct ChorezApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

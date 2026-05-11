import CloudKit
import SwiftData
import SwiftUI
import UIKit

/// Application entry point.
///
/// Owns the live `ModelContainer` and the `AppEnvironment` DI container.
/// Both are injected at the scene root so every view can resolve
/// repositories via `@Environment(AppEnvironment.self)` and SwiftData
/// types via `@Environment(\.modelContext)`.
@main
struct ChorezApp: App {
    /// `UIApplicationDelegateAdaptor` is the SwiftUI bridge for the
    /// AppDelegate methods that have no SwiftUI equivalent. We need it
    /// purely so iOS can hand us the `CKShare.Metadata` when the spouse
    /// accepts an invite link — that path is only reachable via the
    /// classic `application(_:userDidAcceptCloudKitShareWith:)` hook.
    @UIApplicationDelegateAdaptor(ChorezAppDelegate.self) private var appDelegate

    private let container: ModelContainer
    private let appEnvironment: AppEnvironment

    init() {
        // UI tests launch with `-UITesting` so each run starts against
        // an in-memory store. Production launches try CloudKit first
        // (so signed real-device builds get parent-pair sync) and fall
        // back to a local-only store when CloudKit init fails — that
        // path matters in two real environments:
        //
        //   1. CI / `make build` with `CODE_SIGNING_ALLOWED=NO`: the
        //      app is unsigned, the entitlement is stripped, CloudKit
        //      refuses to initialise. We still want the app to launch
        //      so the UI smoke test passes.
        //   2. Devices with no iCloud account signed in: CloudKit
        //      init can still succeed (it queues until iCloud is
        //      reachable) but if the SDK ever changes that we don't
        //      want the app to crash.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let schema = Schema(ChorezSchema.allModels)
        self.container = Self.makeContainer(schema: schema, inMemory: inMemory)
        self.appEnvironment = AppEnvironment(context: container.mainContext)
    }

    private static func makeContainer(schema: Schema, inMemory: Bool) -> ModelContainer {
        if inMemory {
            return forceContainer(
                schema: schema,
                configuration: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        // `ModelConfiguration(cloudKitDatabase: ...)` returns
        // synchronously even when CloudKit will fail later — the
        // entitlement check happens the first time CoreData+CloudKit
        // tries to ping the container, well after init. Wrapping the
        // init in `try?` doesn't catch that. The reliable
        // discriminator is the target environment: simulators don't
        // get entitlements applied under `CODE_SIGNING_ALLOWED=NO`
        // (the path `make build` and CI both use). Real-device
        // signed builds always get them, so this `#if` cleanly maps
        // to "CloudKit usable here?".
        #if targetEnvironment(simulator)
        let configuration = ModelConfiguration()
        #else
        let configuration = ModelConfiguration(
            cloudKitDatabase: .private("iCloud.com.glarsen.chorez")
        )
        #endif
        return forceContainer(schema: schema, configuration: configuration)
    }

    private static func forceContainer(schema: Schema,
                                       configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Local-only store init failing means the device is broken
            // (no disk, no memory). Nothing useful to fall back to;
            // crash loudly so the failure surfaces in dev/CI.
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

/// Catches share-accept hand-offs from iOS.
///
/// When the spouse taps the share-invite link iOS launches Chorez and
/// fires `application(_:userDidAcceptCloudKitShareWith:)` on the app
/// delegate. SwiftUI has no equivalent modifier, so the
/// `UIApplicationDelegateAdaptor` above keeps this tiny class in place
/// just to forward the metadata to `acceptShareInvitation(_:)`. The
/// `CKAcceptSharesOperation` it runs is fire-and-forget — failures are
/// logged because there's no relevant UI to surface them in.
@MainActor
final class ChorezAppDelegate: NSObject, UIApplicationDelegate {
    /// Same container identifier the rest of the app uses. Hard-coded
    /// here rather than threaded through env so the delegate can run
    /// before SwiftUI's view tree exists.
    private static let cloudKitContainerIdentifier = "iCloud.com.glarsen.chorez"

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            let result = await acceptShareInvitation(
                metadata,
                cloudKitContainerIdentifier: Self.cloudKitContainerIdentifier
            )
            if case .failure(let error) = result {
                // No surface to alert from at this stage of launch.
                // The spouse will see an "empty household" if accept
                // fails silently — annoying but recoverable by tapping
                // the invite link again.
                print("acceptShareInvitation failed: \(error)")
            }
        }
    }
}

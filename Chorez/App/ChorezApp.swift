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

    private let syncCoordinator: CKSyncEngineCoordinator?
    private let syncReceiver: SyncReceiver?

    init() {
        // UI tests launch with `-UITesting` so each run starts against
        // an in-memory store. Production launches use a vanilla
        // SwiftData store on disk and hand CloudKit duties to
        // `CKSyncEngineCoordinator` (Phase 1.5 — see
        // `docs/plans/phase-1-5-sync.md`). The previous PR3
        // `ModelConfiguration(cloudKitDatabase: ...)` SwiftData CK
        // binding is gone: SwiftData's auto-managed zone can't be
        // shared, so we now route every CloudKit write through our
        // own engine into the shareable `ChorezSharedZone`.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let schema = Schema(ChorezSchema.allModels)
        self.container = Self.makeContainer(schema: schema, inMemory: inMemory)

        // Sync engine is real on signed real-device builds only.
        // Simulator / `-UITesting` paths skip it — entitlements don't
        // apply in those modes, so attempting CloudKit init would
        // crash async when the SDK first tries to authenticate.
        let coordinator: CKSyncEngineCoordinator?
        let receiver: SyncReceiver?
        #if targetEnvironment(simulator)
        coordinator = nil
        receiver = nil
        #else
        if inMemory {
            coordinator = nil
            receiver = nil
        } else {
            let live = CKSyncEngineCoordinator(
                containerIdentifier: "iCloud.com.glarsen.chorez"
            )
            coordinator = live
            receiver = SyncReceiver(context: container.mainContext, syncEngine: live)
        }
        #endif
        self.syncCoordinator = coordinator
        self.syncReceiver = receiver

        // `-FakeDate=YYYY-MM-DD` lets dev sanity-checks and UI tests
        // pin "now" to a specific calendar day so the Phase 1.6
        // weekday-recurrence gate is exercisable without waiting for
        // the real day to roll. Defaults to wall-clock `.now`.
        let dateProvider: () -> Date = Self.dateProviderFromArguments()
        self.appEnvironment = AppEnvironment(context: container.mainContext,
                                             syncEngine: coordinator,
                                             dateProvider: dateProvider)
    }

    /// Parses `-FakeDate=YYYY-MM-DD` out of the launch arguments and
    /// returns a date provider pinned to that day's noon (noon to
    /// avoid `startOfDay` boundary surprises across timezones).
    /// Returns `{ .now }` when the argument is absent or malformed.
    private static func dateProviderFromArguments() -> () -> Date {
        guard let arg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("-FakeDate=")
        }) else { return { .now } }
        let raw = String(arg.dropFirst("-FakeDate=".count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        guard var date = formatter.date(from: raw) else { return { .now } }
        // Bump to noon local time so a startOfDay-roundtrip is stable.
        date = Calendar.current.date(byAdding: .hour, value: 12, to: date) ?? date
        return { date }
    }

    private static func makeContainer(schema: Schema, inMemory: Bool) -> ModelContainer {
        // Vanilla SwiftData configurations only — CloudKit auto-sync
        // is intentionally absent (Phase 1.5 hands replication to
        // `CKSyncEngineCoordinator`). In-memory for tests, on-disk
        // for everything else.
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // ModelContainer init failing means the device is broken
            // (no disk, no memory). Nothing useful to fall back to;
            // crash loudly so the failure surfaces in dev/CI.
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // Run the per-launch boot sequence once per scene:
                    // (1) start the sync engine so inbound subscriptions
                    //     and the outbound queue come online, (2) hook
                    //     the inbound stream into SwiftData via
                    //     `SyncReceiver`, (3) run PR1's auto-fill hook
                    //     so today's chores exist. The order matters:
                    //     start before receiver so the receiver only
                    //     sees events from a live engine; auto-fill
                    //     last so it sees inbound rows that may have
                    //     arrived during sync.
                    if let syncCoordinator {
                        try? await syncCoordinator.start()
                    }
                    syncReceiver?.start()
                    try? appEnvironment.chores.autoFillTodayIfNeeded(
                        now: appEnvironment.dateProvider()
                    )
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
            switch result {
            case .success:
                // Persist that this device is now a participant so
                // `CKSyncEngineCoordinator.persistedRole()` returns
                // `.participant` on the next start (next launch).
                // Sync engages on relaunch — UX is documented in the
                // Settings footer.
                CKSyncEngineCoordinator.markAsParticipant()
            case .failure(let error):
                // No surface to alert from at this stage of launch.
                // The spouse will see an "empty household" if accept
                // fails silently — annoying but recoverable by tapping
                // the invite link again.
                print("acceptShareInvitation failed: \(error)")
            }
        }
    }
}

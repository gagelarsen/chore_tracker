import Foundation
import SwiftData

/// Dependency-injection container for view models.
///
/// Holds one instance of each repository, scoped to a single
/// `ModelContext`. Built once in `ChorezApp` and threaded through the
/// view hierarchy via `@Environment(AppEnvironment.self)` — the
/// SwiftUI-5+ pattern that lets any `@Observable` class be
/// environment-injected without defining a custom `EnvironmentKey`.
///
/// Marked `@Observable` purely so the `@Environment(Type.self)` lookup
/// works; there is no published state on the container itself. View
/// models hold the repositories they need and publish their own
/// observable state.
@MainActor
@Observable
public final class AppEnvironment {
    public let households: HouseholdRepository
    public let kids: KidRepository
    public let chores: ChoreRepository
    public let rewards: RewardRepository
    public let events: EventRepository

    /// Optional sync engine for Phase 1.5 cross-account replication.
    /// `nil` in the in-memory test container and on the simulator
    /// without entitlements (see `ChorezApp.init`). Repositories
    /// detect the nil case and skip outbound push.
    public let syncEngine: (any SharedZoneSyncEngine)?

    /// Builds the container against a `ModelContext`. `dateProvider`
    /// defaults to wall-clock `.now` and exists so tests (or a future
    /// time-travel feature) can pin the engine's notion of "now"
    /// without monkey-patching globals.
    public init(context: ModelContext,
                syncEngine: (any SharedZoneSyncEngine)? = nil,
                dateProvider: @escaping () -> Date = { .now }) {
        self.syncEngine = syncEngine
        self.households = HouseholdRepository(context: context,
                                              syncEngine: syncEngine,
                                              dateProvider: dateProvider)
        self.kids = KidRepository(context: context, syncEngine: syncEngine)
        self.chores = ChoreRepository(context: context, syncEngine: syncEngine)
        self.rewards = RewardRepository(context: context, syncEngine: syncEngine)
        self.events = EventRepository(context: context)
    }
}

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

    /// Builds the container against a `ModelContext`. `dateProvider`
    /// defaults to wall-clock `.now` and exists so tests (or a future
    /// time-travel feature) can pin the engine's notion of "now"
    /// without monkey-patching globals.
    public init(context: ModelContext, dateProvider: @escaping () -> Date = { .now }) {
        self.households = HouseholdRepository(context: context, dateProvider: dateProvider)
        self.kids = KidRepository(context: context)
        self.chores = ChoreRepository(context: context)
        self.rewards = RewardRepository(context: context)
        self.events = EventRepository(context: context)
    }
}

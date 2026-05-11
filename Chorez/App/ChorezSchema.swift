import Foundation
import SwiftData

/// Canonical list of every `@Model` type the app persists.
///
/// One source of truth used by the live `ModelContainer` in `ChorezApp`
/// and by `RepoFixture.makeContext()` in tests, so a missing model can't
/// silently drift between production and the suite.
public enum ChorezSchema {
    public static let allModels: [any PersistentModel.Type] = [
        Household.self,
        Kid.self,
        ChoreTemplate.self,
        ChoreInstance.self,
        Reward.self,
        RewardRedemption.self,
        Event.self
    ]
}

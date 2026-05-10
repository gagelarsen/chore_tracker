import Foundation
import SwiftData
@testable import Chorez

// Shared in-memory ModelContainer setup for the repository test suites.
// Each test calls `makeContext()` to get a fresh store so persistence
// behavior is exercised end-to-end without cross-test leakage.

@MainActor
enum RepoFixture {
    /// All seven Phase 1 entities registered against a fresh in-memory
    /// store. Starting point for every repository test.
    static func makeContext() throws -> ModelContext {
        let schema = Schema([
            Household.self, Kid.self,
            ChoreTemplate.self, ChoreInstance.self,
            Reward.self, RewardRedemption.self,
            Event.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// Bootstrap a household + named kids so household-scoped tests can
    /// jump straight to assertions.
    @discardableResult
    static func seed(context: ModelContext, kidNames: [String] = []) throws -> Household {
        let household = Household(name: "Family")
        context.insert(household)
        for (idx, name) in kidNames.enumerated() {
            context.insert(Kid(householdID: household.id, name: name, displayOrder: idx))
        }
        try context.save()
        return household
    }
}

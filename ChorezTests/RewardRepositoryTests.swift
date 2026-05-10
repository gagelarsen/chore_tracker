import Foundation
import Testing
@testable import Chorez

@MainActor
@Suite("RewardRepository")
struct RewardRepositoryTests {

    @Test("all returns rewards sorted by points then name")
    func sortedByPoints() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = RewardRepository(context: context)

        try repo.create(householdID: household.id, name: "Phone", points: 100)
        try repo.create(householdID: household.id, name: "Candy", points: 10)
        try repo.create(householdID: household.id, name: "Sticker", points: 10)

        let names = try repo.all().map(\.name)
        #expect(names == ["Candy", "Sticker", "Phone"])
    }

    @Test("active filters out deactivated rewards")
    func activeFilters() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = RewardRepository(context: context)

        _ = try repo.create(householdID: household.id, name: "A", points: 5)
        let inactive = try repo.create(householdID: household.id, name: "B", points: 5)
        try repo.update(inactive, active: false)

        let names = try repo.active().map(\.name)
        #expect(names == ["A"])
    }

    @Test("update mutates only the named fields")
    func partialUpdate() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = RewardRepository(context: context)

        let reward = try repo.create(householdID: household.id, name: "Snack", points: 5)
        try repo.update(reward, points: 12)

        #expect(reward.name == "Snack")
        #expect(reward.points == 12)
        #expect(reward.active == true)
    }

    @Test("delete removes the row")
    func deleteRemoves() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = RewardRepository(context: context)

        let reward = try repo.create(householdID: household.id, name: "Snack", points: 5)
        try repo.delete(reward)

        #expect(try repo.all().isEmpty)
    }
}

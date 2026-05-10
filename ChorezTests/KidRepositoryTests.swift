import Foundation
import Testing
@testable import Chorez

@MainActor
@Suite("KidRepository")
struct KidRepositoryTests {

    @Test("create assigns sequential displayOrder when omitted")
    func createAssignsOrder() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = KidRepository(context: context)

        try repo.create(householdID: household.id, name: "Anna")
        try repo.create(householdID: household.id, name: "Ben")

        let all = try repo.all()
        #expect(all.map(\.name) == ["Anna", "Ben"])
        #expect(all.map(\.displayOrder) == [0, 1])
    }

    @Test("all sorts by displayOrder then name")
    func allSortedByDisplayOrder() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = KidRepository(context: context)

        try repo.create(householdID: household.id, name: "Zed", displayOrder: 0)
        try repo.create(householdID: household.id, name: "Anna", displayOrder: 1)
        try repo.create(householdID: household.id, name: "Ben", displayOrder: 1)

        let names = try repo.all().map(\.name)
        #expect(names == ["Zed", "Anna", "Ben"])
    }

    @Test("find returns nil for unknown id")
    func findUnknown() throws {
        let context = try RepoFixture.makeContext()
        try RepoFixture.seed(context: context)
        let repo = KidRepository(context: context)

        #expect(try repo.find(id: UUID()) == nil)
    }

    @Test("rename updates name in place")
    func renameUpdates() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let repo = KidRepository(context: context)

        let kid = try repo.create(householdID: household.id, name: "Old")
        try repo.rename(kid, to: "New")

        let fetched = try #require(try repo.find(id: kid.id))
        #expect(fetched.name == "New")
    }

    @Test("delete cascades to assigned templates and pending instances")
    func deleteCascades() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context)
        let kidRepo = KidRepository(context: context)
        let choreRepo = ChoreRepository(context: context)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let kid = try kidRepo.create(householdID: household.id, name: "Anna")
        household.lastAutoFillDate = Calendar.current.startOfDay(for: now)
        try context.save()

        let template = try choreRepo.createTemplate(
            householdID: household.id, name: "Dishes",
            points: 5, assignedKidID: kid.id, now: now
        )
        let pendingBefore = try choreRepo.instances(forDate: now)
        #expect(pendingBefore.count == 1)
        #expect(pendingBefore.first?.templateID == template.id)

        try kidRepo.delete(kid)

        let templatesAfter = try choreRepo.templates(householdID: household.id)
        let instancesAfter = try choreRepo.instances(forDate: now)
        #expect(templatesAfter.isEmpty)
        #expect(instancesAfter.isEmpty)
    }
}

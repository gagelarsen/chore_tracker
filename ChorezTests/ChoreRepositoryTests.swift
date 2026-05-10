import Foundation
import Testing
@testable import Chorez

@MainActor
@Suite("ChoreRepository")
struct ChoreRepositoryTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static var today: Date { Calendar.current.startOfDay(for: now) }

    @Test("createTemplate before same-day auto-fill leaves today empty")
    func createTemplateBeforeAutoFill() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)

        try repo.createTemplate(householdID: household.id, name: "Dishes",
                                points: 5, assignedKidID: kid.id, now: Self.now)

        #expect(try repo.instances(forDate: Self.now).isEmpty)
    }

    @Test("createTemplate after auto-fill also creates today's instance")
    func createTemplateAfterAutoFill() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)

        household.lastAutoFillDate = Self.today
        try context.save()

        try repo.createTemplate(householdID: household.id, name: "Dishes",
                                points: 5, assignedKidID: kid.id, now: Self.now)

        let instances = try repo.instances(forDate: Self.now)
        #expect(instances.count == 1)
        #expect(instances.first?.assignedKidID == kid.id)
    }

    @Test("autoFillTodayIfNeeded creates one instance per active template")
    func autoFillCreatesInstances() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A", "B"])
        let kids = try KidRepository(context: context).all()
        let repo = ChoreRepository(context: context)

        try repo.createTemplate(householdID: household.id, name: "Dishes",
                                points: 5, assignedKidID: kids[0].id, now: Self.now)
        try repo.createTemplate(householdID: household.id, name: "Trash",
                                points: 3, assignedKidID: kids[1].id, now: Self.now)

        let added = try repo.autoFillTodayIfNeeded(now: Self.now)
        #expect(added == 2)

        let instances = try repo.instances(forDate: Self.now)
        #expect(instances.count == 2)
        #expect(Set(instances.map(\.assignedKidID)) == Set(kids.map(\.id)))
    }

    @Test("autoFillTodayIfNeeded is idempotent within the same day")
    func autoFillSameDayNoop() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)
        _ = household

        try repo.createTemplate(householdID: household.id, name: "Dishes",
                                points: 5, assignedKidID: kid.id, now: Self.now)

        _ = try repo.autoFillTodayIfNeeded(now: Self.now)
        let second = try repo.autoFillTodayIfNeeded(now: Self.now)
        #expect(second == 0)
        #expect(try repo.instances(forDate: Self.now).count == 1)
    }

    @Test("autoFillTodayIfNeeded fires again on the next day")
    func autoFillNextDay() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)

        try repo.createTemplate(householdID: household.id, name: "Dishes",
                                points: 5, assignedKidID: kid.id, now: Self.now)
        _ = try repo.autoFillTodayIfNeeded(now: Self.now)

        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Self.now)!
        let added = try repo.autoFillTodayIfNeeded(now: nextDay)
        #expect(added == 1)
        #expect(household.lastAutoFillDate == Calendar.current.startOfDay(for: nextDay))
    }

    @Test("autoFillTodayIfNeeded is a no-op when there is no household")
    func autoFillNoHousehold() throws {
        let context = try RepoFixture.makeContext()
        let repo = ChoreRepository(context: context)
        #expect(try repo.autoFillTodayIfNeeded(now: Self.now) == 0)
    }

    @Test("autoFillTodayIfNeeded skips inactive templates")
    func autoFillSkipsInactive() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)

        _ = try repo.createTemplate(householdID: household.id, name: "On",
                                    points: 5, assignedKidID: kid.id, now: Self.now)
        let inactive = try repo.createTemplate(householdID: household.id, name: "Off",
                                               points: 5, assignedKidID: kid.id, now: Self.now)
        try repo.updateTemplate(inactive, active: false)

        let added = try repo.autoFillTodayIfNeeded(now: Self.now)
        #expect(added == 1)
        let instances = try repo.instances(forDate: Self.now)
        #expect(instances.first?.name == "On")
    }

    @Test("createAdHocInstance normalises date to startOfDay and has no templateID")
    func adHocNormalisesDate() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)

        let mid = Calendar.current.date(byAdding: .hour, value: 14, to: Self.today)!
        let instance = try repo.createAdHocInstance(householdID: household.id, kidID: kid.id,
                                                    name: "Extra", points: 2, on: mid)
        #expect(instance.templateID == nil)
        #expect(instance.date == Self.today)
    }

    @Test("deleteTemplate removes pending instances; completed ones stay")
    func deleteTemplateCascadesPendingOnly() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let repo = ChoreRepository(context: context)
        household.lastAutoFillDate = Self.today
        try context.save()

        let template = try repo.createTemplate(householdID: household.id, name: "Dishes",
                                               points: 5, assignedKidID: kid.id, now: Self.now)
        let instance = try #require(try repo.instances(forDate: Self.now).first)
        instance.status = .done
        instance.completedAt = Self.now
        try context.save()

        try repo.deleteTemplate(template)

        let remaining = try repo.instances(forDate: Self.now)
        #expect(remaining.count == 1)
        #expect(remaining.first?.status == .done)
    }
}

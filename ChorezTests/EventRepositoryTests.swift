import Foundation
import Testing
@testable import Chorez

@MainActor
@Suite("EventRepository")
struct EventRepositoryTests {

    @Test("all returns events sorted newest-first")
    func sortedNewestFirst() throws {
        let context = try RepoFixture.makeContext()
        try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]

        // Insert events with deterministic timestamps; EventRepository
        // owns the read side so we drive writes through `context.insert`
        // directly here (writes-through-engine are covered by the
        // HouseholdRepository suite).
        let early = Event(kidID: kid.id, payload: .awardGiven(points: 1),
                          occurredAt: Date(timeIntervalSince1970: 1_000))
        let mid = Event(kidID: kid.id, payload: .awardGiven(points: 2),
                        occurredAt: Date(timeIntervalSince1970: 2_000))
        let late = Event(kidID: kid.id, payload: .awardGiven(points: 3),
                         occurredAt: Date(timeIntervalSince1970: 3_000))
        for event in [early, mid, late] { context.insert(event) }
        try context.save()

        let fetched = try EventRepository(context: context).all()
        #expect(fetched.map(\.id) == [late.id, mid.id, early.id])
    }

    @Test("forKid filters by kidID")
    func forKidFilters() throws {
        let context = try RepoFixture.makeContext()
        try RepoFixture.seed(context: context, kidNames: ["A", "B"])
        let kids = try KidRepository(context: context).all()

        context.insert(Event(kidID: kids[0].id, payload: .awardGiven(points: 1),
                             occurredAt: Date(timeIntervalSince1970: 1_000)))
        context.insert(Event(kidID: kids[1].id, payload: .awardGiven(points: 2),
                             occurredAt: Date(timeIntervalSince1970: 2_000)))
        context.insert(Event(kidID: nil, payload: .dayClosed(previousBalance: 0),
                             occurredAt: Date(timeIntervalSince1970: 3_000)))
        try context.save()

        let aEvents = try EventRepository(context: context).forKid(kids[0].id)
        #expect(aEvents.count == 1)
        #expect(aEvents.first?.payload == .awardGiven(points: 1))
    }

    @Test("all returns empty on an empty store")
    func emptyStore() throws {
        let context = try RepoFixture.makeContext()
        #expect(try EventRepository(context: context).all().isEmpty)
    }
}

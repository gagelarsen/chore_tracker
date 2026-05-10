import Foundation
import SwiftData
import Testing
@testable import Chorez

@MainActor
@Suite("HouseholdRepository.applyEngine bottleneck")
struct HouseholdRepositoryTests {

    /// Fixed clock pinned to a midday timestamp; the engine's date math
    /// is the only thing that touches `Calendar`, and midday avoids the
    /// `startOfDay` boundary so closeOutDay assertions stay stable
    /// across host timezones.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func repo(_ context: ModelContext) -> HouseholdRepository {
        HouseholdRepository(context: context, dateProvider: { Self.now })
    }

    @Test("current returns nil before any household is created")
    func currentEmpty() throws {
        let context = try RepoFixture.makeContext()
        #expect(try repo(context).current() == nil)
    }

    @Test("createIfMissing creates first time, returns existing on subsequent calls")
    func createIfMissingIdempotent() throws {
        let context = try RepoFixture.makeContext()
        let first = try repo(context).createIfMissing(name: "Family")
        let second = try repo(context).createIfMissing(name: "Different")
        #expect(first.id == second.id)
        #expect(second.name == "Family")
    }

    @Test("snapshot is nil before household creation")
    func snapshotEmptyStore() throws {
        let context = try RepoFixture.makeContext()
        #expect(try repo(context).snapshot() == nil)
    }

    @Test("applyEngine throws when called before the household is initialised")
    func applyEngineEmptyStore() throws {
        let context = try RepoFixture.makeContext()
        // Calling the engine before bootstrapping the household is a
        // programmer error; the repository should surface it rather
        // than silently succeed.
        do {
            // `CloseOutError` is the uninhabited empty-enum case in the
            // engine surface and pins the generic `E` so the identity
            // closure type-checks.
            let _: Result<Void, CloseOutError> = try repo(context)
                .applyEngine { state, _ in .success(state) }
            Issue.record("Expected HouseholdRepositoryError.householdNotInitialized to be thrown")
        } catch HouseholdRepositoryError.householdNotInitialized {
            // expected
        }
    }

    @Test("applyAward updates balance and inserts event row")
    func applyAwardRoundtrip() throws {
        let context = try RepoFixture.makeContext()
        try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]

        let result = try repo(context).applyAward(kidID: kid.id, points: 8)
        if case .failure(let error) = result { Issue.record("Unexpected failure: \(error)") }

        let fetchedKid = try #require(try KidRepository(context: context).find(id: kid.id))
        #expect(fetchedKid.currentDailyBalance == 8)

        let events = try EventRepository(context: context).forKid(kid.id)
        #expect(events.count == 1)
        #expect(events.first?.payload == .awardGiven(points: 8))
    }

    @Test("applyAward returns wouldGoNegative; nothing persisted")
    func applyAwardFailureDoesNotPersist() throws {
        let context = try RepoFixture.makeContext()
        try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]

        let result = try repo(context).applyAward(kidID: kid.id, points: -1)
        // `Result<Void, _>` isn't Equatable (Void isn't), so case-match
        // rather than compare with `==`.
        guard case .failure(let error) = result else {
            Issue.record("Expected wouldGoNegative, got success")
            return
        }
        #expect(error == .wouldGoNegative)

        let fetched = try #require(try KidRepository(context: context).find(id: kid.id))
        #expect(fetched.currentDailyBalance == 0)
        #expect(try EventRepository(context: context).all().isEmpty)
    }

    @Test("applyChoreCompletion: instance done, kid credited, event recorded")
    func applyChoreCompletionRoundtrip() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let choreRepo = ChoreRepository(context: context)
        household.lastAutoFillDate = Calendar.current.startOfDay(for: Self.now)
        try context.save()
        try choreRepo.createTemplate(householdID: household.id, name: "Dishes",
                                     points: 7, assignedKidID: kid.id, now: Self.now)
        let instance = try #require(try choreRepo.instances(forDate: Self.now).first)

        let result = try repo(context).applyChoreCompletion(instanceID: instance.id)
        if case .failure(let error) = result { Issue.record("Unexpected failure: \(error)") }

        let refreshed = try #require(try choreRepo.instances(forDate: Self.now).first)
        #expect(refreshed.status == .done)
        #expect(refreshed.completedAt == Self.now)

        let refreshedKid = try #require(try KidRepository(context: context).find(id: kid.id))
        #expect(refreshedKid.currentDailyBalance == 7)
    }

    @Test("redeemReward debits balance and inserts a redemption row")
    func redeemRewardRoundtrip() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A"])
        let kid = try KidRepository(context: context).all()[0]
        let reward = try RewardRepository(context: context).create(householdID: household.id,
                                                                   name: "Sticker", points: 4)
        _ = try repo(context).applyAward(kidID: kid.id, points: 10)

        let result = try repo(context).redeemReward(kidID: kid.id, rewardID: reward.id)
        if case .failure(let error) = result { Issue.record("Unexpected failure: \(error)") }

        let refreshedKid = try #require(try KidRepository(context: context).find(id: kid.id))
        #expect(refreshedKid.currentDailyBalance == 6)

        let redemptions = try context.fetch(FetchDescriptor<RewardRedemption>())
        #expect(redemptions.count == 1)
        #expect(redemptions.first?.points == 4)
        #expect(redemptions.first?.kidID == kid.id)
    }

    @Test("closeOutDay zeroes balances, deletes today's instances, emits per-kid events")
    func closeOutDayRoundtrip() throws {
        let context = try RepoFixture.makeContext()
        let household = try RepoFixture.seed(context: context, kidNames: ["A", "B"])
        let kids = try KidRepository(context: context).all()
        let choreRepo = ChoreRepository(context: context)
        household.lastAutoFillDate = Calendar.current.startOfDay(for: Self.now)
        try context.save()
        for kid in kids {
            try choreRepo.createTemplate(householdID: household.id, name: "T-\(kid.name)",
                                         points: 3, assignedKidID: kid.id, now: Self.now)
        }
        _ = try repo(context).applyAward(kidID: kids[0].id, points: 5)

        let result = try repo(context).closeOutDay()
        if case .failure = result { Issue.record("Unexpected failure on closeOutDay") }

        let refreshed = try KidRepository(context: context).all()
        #expect(refreshed.allSatisfy { $0.currentDailyBalance == 0 })
        #expect(try choreRepo.instances(forDate: Self.now).isEmpty)
        let events = try EventRepository(context: context).all()
        let dayClosedCount = events.filter { event in
            if case .dayClosed = event.payload { return true } else { return false }
        }.count
        #expect(dayClosedCount == 2)
    }
}

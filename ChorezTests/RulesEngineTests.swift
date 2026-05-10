import Foundation
import Testing
@testable import Chorez

// Pure rules engine tests. No SwiftData involved — every fixture is a
// literal `HouseholdState` so failures point straight at the offending
// rule rather than at persistence wiring.

// MARK: - Fixtures

/// Compact builder for engine tests. Keeps test bodies focused on the
/// assertion, not on snapshot construction. Each test customises only the
/// fields it cares about.
private enum Fixture {
    static let householdID = UUID()
    static let kidA = UUID()
    static let kidB = UUID()
    static let rewardActive = UUID()
    static let rewardInactive = UUID()
    static let templateA = UUID()

    static func household() -> HouseholdSnapshot {
        HouseholdSnapshot(id: householdID, name: "Test", createdAt: Date(timeIntervalSince1970: 0))
    }

    static func kid(id: UUID, name: String = "K", order: Int = 0, balance: Int = 0) -> KidSnapshot {
        KidSnapshot(id: id, householdID: householdID, name: name,
                    displayOrder: order, currentDailyBalance: balance)
    }

    static func template(id: UUID = templateA,
                         kid: UUID = kidA,
                         points: Int = 5,
                         active: Bool = true) -> ChoreTemplateSnapshot {
        ChoreTemplateSnapshot(id: id, householdID: householdID,
                              name: "Dishes", points: points,
                              assignedKidID: kid, recurrence: .daily, active: active)
    }

    static func instance(id: UUID = UUID(),
                         kid: UUID = kidA,
                         points: Int = 5,
                         date: Date = Date(timeIntervalSince1970: 1_700_000_000),
                         status: ChoreStatus = .pending) -> ChoreInstanceSnapshot {
        ChoreInstanceSnapshot(id: id, templateID: templateA, householdID: householdID,
                              name: "Dishes", points: points, assignedKidID: kid,
                              date: date, status: status, completedAt: nil)
    }

    static func reward(id: UUID = rewardActive,
                       points: Int = 10,
                       active: Bool = true) -> RewardSnapshot {
        RewardSnapshot(id: id, householdID: householdID, name: "Ice cream",
                       points: points, active: active)
    }

    static func state(kids: [KidSnapshot] = [],
                      templates: [ChoreTemplateSnapshot] = [],
                      instances: [ChoreInstanceSnapshot] = [],
                      rewards: [RewardSnapshot] = [],
                      redemptions: [RewardRedemptionSnapshot] = [],
                      events: [EventSnapshot] = []) -> HouseholdState {
        HouseholdState(household: household(),
                       kids: kids, templates: templates, instances: instances,
                       rewards: rewards, redemptions: redemptions, events: events)
    }

    static let now: Date = Date(timeIntervalSince1970: 1_700_086_400)  // arbitrary fixed clock
}

// MARK: - applyChoreCompletion

@Suite("applyChoreCompletion")
struct ApplyChoreCompletionTests {

    @Test("Happy path: pending instance is marked done, kid is credited, event appended")
    func happyPath() throws {
        let inst = Fixture.instance(points: 7)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 3)],
            instances: [inst]
        )

        let result = RulesEngine.applyChoreCompletion(state, instanceID: inst.id, at: Fixture.now)
        let new = try result.get()

        #expect(new.instances[0].status == .done)
        #expect(new.instances[0].completedAt == Fixture.now)
        #expect(new.kids[0].currentDailyBalance == 10)
        #expect(new.events.count == 1)
        #expect(new.events[0].payload == .choreCompleted(instanceID: inst.id, points: 7))
        #expect(new.events[0].kidID == Fixture.kidA)
    }

    @Test("Zero-point chore: instance marked done, event appended, balance unchanged")
    func zeroPoints() throws {
        let inst = Fixture.instance(points: 0)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 4)],
            instances: [inst]
        )

        let new = try RulesEngine.applyChoreCompletion(state, instanceID: inst.id, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 4)
        #expect(new.instances[0].status == .done)
        #expect(new.events.count == 1)
    }

    @Test("Instance not found")
    func instanceNotFound() {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA)])
        let result = RulesEngine.applyChoreCompletion(state, instanceID: UUID(), at: Fixture.now)
        #expect(result == .failure(.instanceNotFound))
    }

    @Test("Already completed: idempotent guard refuses second credit")
    func alreadyCompleted() {
        let inst = Fixture.instance(status: .done)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 5)],
            instances: [inst]
        )

        let result = RulesEngine.applyChoreCompletion(state, instanceID: inst.id, at: Fixture.now)
        #expect(result == .failure(.alreadyCompleted))
    }

    @Test("Kid for instance not found (defensive)")
    func kidNotFound() {
        let inst = Fixture.instance(kid: UUID())  // unknown kid
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA)],
            instances: [inst]
        )

        let result = RulesEngine.applyChoreCompletion(state, instanceID: inst.id, at: Fixture.now)
        #expect(result == .failure(.kidNotFound))
    }
}

// MARK: - applyAward

@Suite("applyAward")
struct ApplyAwardTests {

    @Test("Positive award credits balance and logs event")
    func positiveAward() throws {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA, balance: 2)])
        let new = try RulesEngine.applyAward(state, kidID: Fixture.kidA, points: 6, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 8)
        #expect(new.events.last?.payload == .awardGiven(points: 6))
        #expect(new.events.last?.kidID == Fixture.kidA)
    }

    @Test("Negative award docks balance when sufficient")
    func negativeAwardSufficient() throws {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA, balance: 10)])
        let new = try RulesEngine.applyAward(state, kidID: Fixture.kidA, points: -4, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 6)
        #expect(new.events.last?.payload == .awardGiven(points: -4))
    }

    @Test("Zero-point award is a no-op on balance but still emits event")
    func zeroAward() throws {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA, balance: 5)])
        let new = try RulesEngine.applyAward(state, kidID: Fixture.kidA, points: 0, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 5)
        #expect(new.events.count == 1)
    }

    @Test("Dock exactly to zero is allowed")
    func dockToZero() throws {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA, balance: 5)])
        let new = try RulesEngine.applyAward(state, kidID: Fixture.kidA, points: -5, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 0)
    }

    @Test("Dock that would go negative is refused")
    func wouldGoNegative() {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA, balance: 3)])
        let result = RulesEngine.applyAward(state, kidID: Fixture.kidA, points: -4, at: Fixture.now)

        #expect(result == .failure(.wouldGoNegative))
    }

    @Test("Unknown kid is refused")
    func unknownKid() {
        let state = Fixture.state(kids: [Fixture.kid(id: Fixture.kidA)])
        let result = RulesEngine.applyAward(state, kidID: UUID(), points: 5, at: Fixture.now)

        #expect(result == .failure(.kidNotFound))
    }
}

// MARK: - redeemReward

@Suite("redeemReward")
struct RedeemRewardTests {

    @Test("Happy path: balance > cost — balance debited, redemption + event appended")
    func happyPath() throws {
        let reward = Fixture.reward(points: 6)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 10)],
            rewards: [reward]
        )

        let new = try RulesEngine.redeemReward(state, kidID: Fixture.kidA,
                                               rewardID: reward.id, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 4)
        #expect(new.redemptions.count == 1)
        let redemption = try #require(new.redemptions.first)
        #expect(redemption.kidID == Fixture.kidA)
        #expect(redemption.rewardID == reward.id)
        #expect(redemption.points == 6)
        #expect(redemption.redeemedAt == Fixture.now)
        // Redemption ID is correlated into the event payload
        #expect(new.events.last?.payload == .rewardRedeemed(
            rewardID: reward.id, redemptionID: redemption.id, points: 6
        ))
    }

    @Test("Exact balance: redemption empties the balance to zero")
    func exactBalance() throws {
        let reward = Fixture.reward(points: 5)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 5)],
            rewards: [reward]
        )

        let new = try RulesEngine.redeemReward(state, kidID: Fixture.kidA,
                                               rewardID: reward.id, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 0)
    }

    @Test("Zero-cost reward: redeems even at zero balance")
    func freeReward() throws {
        let reward = Fixture.reward(points: 0)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 0)],
            rewards: [reward]
        )

        let new = try RulesEngine.redeemReward(state, kidID: Fixture.kidA,
                                               rewardID: reward.id, at: Fixture.now).get()

        #expect(new.kids[0].currentDailyBalance == 0)
        #expect(new.redemptions.count == 1)
    }

    @Test("Insufficient balance is refused; state untouched")
    func insufficientBalance() {
        let reward = Fixture.reward(points: 10)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 4)],
            rewards: [reward]
        )

        let result = RulesEngine.redeemReward(state, kidID: Fixture.kidA,
                                              rewardID: reward.id, at: Fixture.now)
        #expect(result == .failure(.insufficientBalance))
    }

    @Test("Inactive reward is refused")
    func inactiveReward() {
        let reward = Fixture.reward(id: Fixture.rewardInactive, points: 1, active: false)
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 100)],
            rewards: [reward]
        )

        let result = RulesEngine.redeemReward(state, kidID: Fixture.kidA,
                                              rewardID: reward.id, at: Fixture.now)
        #expect(result == .failure(.rewardInactive))
    }

    @Test("Unknown reward is refused")
    func unknownReward() {
        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA, balance: 10)]
        )

        let result = RulesEngine.redeemReward(state, kidID: Fixture.kidA,
                                              rewardID: UUID(), at: Fixture.now)
        #expect(result == .failure(.rewardNotFound))
    }

    @Test("Unknown kid is refused")
    func unknownKid() {
        let state = Fixture.state(rewards: [Fixture.reward()])
        let result = RulesEngine.redeemReward(state, kidID: UUID(),
                                              rewardID: Fixture.rewardActive, at: Fixture.now)
        #expect(result == .failure(.kidNotFound))
    }
}

// MARK: - closeOutDay

@Suite("closeOutDay (Phase 1 stub)")
struct CloseOutDayTests {

    /// 12:00 UTC on a fixed day; using midday avoids ambiguity at the
    /// `startOfDay` boundary when paired with a Calendar that uses local
    /// time. Tests compare deletion against `Calendar.current.startOfDay`
    /// of this value, so they're stable on any host timezone.
    private static let midday = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Zeroes all balances and emits one dayClosed event per kid")
    func zeroesBalances() throws {
        let state = Fixture.state(
            kids: [
                Fixture.kid(id: Fixture.kidA, name: "A", order: 0, balance: 12),
                Fixture.kid(id: Fixture.kidB, name: "B", order: 1, balance: 0)
            ]
        )

        let new = try RulesEngine.closeOutDay(state, at: Self.midday).get()

        #expect(new.kids.allSatisfy { $0.currentDailyBalance == 0 })
        #expect(new.events.count == 2)
        let payloads = new.events.map(\.payload)
        #expect(payloads.contains(.dayClosed(previousBalance: 12)))
        #expect(payloads.contains(.dayClosed(previousBalance: 0)))
    }

    @Test("Removes today's instances; preserves prior days'")
    func removesTodaysInstancesOnly() throws {
        let today = Calendar.current.startOfDay(for: Self.midday)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let todaysDone = Fixture.instance(id: UUID(), date: today, status: .done)
        let todaysPending = Fixture.instance(id: UUID(), date: today, status: .pending)
        let yesterdays = Fixture.instance(id: UUID(), date: yesterday, status: .pending)

        let state = Fixture.state(
            kids: [Fixture.kid(id: Fixture.kidA)],
            instances: [todaysDone, todaysPending, yesterdays]
        )

        let new = try RulesEngine.closeOutDay(state, at: Self.midday).get()

        #expect(new.instances.count == 1)
        #expect(new.instances.first?.id == yesterdays.id)
    }

    @Test("Empty household is a no-op")
    func emptyHousehold() throws {
        let state = Fixture.state()
        let new = try RulesEngine.closeOutDay(state, at: Self.midday).get()

        #expect(new.kids.isEmpty)
        #expect(new.instances.isEmpty)
        #expect(new.events.isEmpty)
    }
}

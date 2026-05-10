import Foundation
import SwiftData

/// CRUD wrapper over `Household` rows, plus the single `applyEngine`
/// bottleneck that routes every rules-engine call from the UI all the
/// way down to SwiftData.
///
/// The bottleneck is what makes the DRY invariants in
/// `00-standards.md` enforceable: views call typed convenience methods
/// (`applyAward`, `redeemReward`, …) on this repository, which all go
/// through `applyEngine`, which is the only path that diffs a new
/// `HouseholdState` back into `ModelContext`. As long as no other code
/// mutates `Kid.currentDailyBalance` etc. directly, the engine remains
/// the sole authority on point math.
@MainActor
public final class HouseholdRepository {
    private let context: ModelContext
    private let dateProvider: () -> Date

    public init(context: ModelContext, dateProvider: @escaping () -> Date = { .now }) {
        self.context = context
        self.dateProvider = dateProvider
    }

    // MARK: - Lookup / create

    public func current() throws -> Household? {
        var descriptor = FetchDescriptor<Household>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Lazily create the (currently sole) household on first launch.
    /// Phase 1 ships one household per device; CloudKit + `CKShare` in
    /// PR3 lets a second device join the same record.
    @discardableResult
    public func createIfMissing(name: String = "Our Family",
                                ownerCloudUserID: String? = nil) throws -> Household {
        if let existing = try current() { return existing }
        let household = Household(name: name,
                                  ownerCloudUserID: ownerCloudUserID,
                                  createdAt: dateProvider())
        context.insert(household)
        try context.save()
        return household
    }

    // MARK: - Snapshot

    /// Read every Phase 1 entity out of `ModelContext` and assemble a
    /// pure `HouseholdState` for the rules engine.
    ///
    /// Returns `nil` when no household has been created yet — the rules
    /// engine has nothing to operate on.
    public func snapshot() throws -> HouseholdState? {
        guard let household = try current() else { return nil }
        let kids = try context.fetch(FetchDescriptor<Kid>()).map(\.snapshot)
        let templates = try context.fetch(FetchDescriptor<ChoreTemplate>()).map(\.snapshot)
        let instances = try context.fetch(FetchDescriptor<ChoreInstance>()).map(\.snapshot)
        let rewards = try context.fetch(FetchDescriptor<Reward>()).map(\.snapshot)
        let redemptions = try context.fetch(FetchDescriptor<RewardRedemption>()).map(\.snapshot)
        // `compactMap`: `Event.snapshot` is nil only if `payloadData` is
        // unreadable JSON — defensive read, fresh writes always succeed.
        let events = try context.fetch(FetchDescriptor<Event>()).compactMap(\.snapshot)
        return HouseholdState(household: household.snapshot,
                              kids: kids,
                              templates: templates,
                              instances: instances,
                              rewards: rewards,
                              redemptions: redemptions,
                              events: events)
    }

    // MARK: - Apply engine (the bottleneck)

    /// Run any rules-engine function and persist the result.
    ///
    /// Storage errors are thrown; rule failures come back inside the
    /// `Result`. Splitting them this way keeps call sites focused on the
    /// business-level outcome — a `RedemptionError.insufficientBalance`
    /// is a normal UI state, while a SwiftData write failure is an
    /// exceptional crash-y situation.
    public func applyEngine<E: Error>(
        _ transform: (HouseholdState, Date) -> Result<HouseholdState, E>
    ) throws -> Result<Void, E> {
        guard let oldState = try snapshot() else {
            // No household yet — the engine has no state to operate on.
            // Treat as a no-op success rather than throwing; the caller
            // either hasn't bootstrapped yet or is exercising an empty
            // store.
            return .success(())
        }
        let now = dateProvider()
        switch transform(oldState, now) {
        case .success(let newState):
            try writeBack(old: oldState, new: newState)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Typed convenience wrappers (call sites for the DRY rules)

    /// The only path that should mark a `ChoreInstance` as done.
    public func applyChoreCompletion(instanceID: UUID) throws -> Result<Void, ChoreCompletionError> {
        try applyEngine { RulesEngine.applyChoreCompletion($0, instanceID: instanceID, at: $1) }
    }

    /// The only path that should mutate `Kid.currentDailyBalance` upward
    /// (or apply a parent-issued dock).
    public func applyAward(kidID: UUID, points: Int) throws -> Result<Void, AwardError> {
        try applyEngine { RulesEngine.applyAward($0, kidID: kidID, points: points, at: $1) }
    }

    /// The only path that should debit balance for a redemption.
    public func redeemReward(kidID: UUID, rewardID: UUID) throws -> Result<Void, RedemptionError> {
        try applyEngine { RulesEngine.redeemReward($0, kidID: kidID, rewardID: rewardID, at: $1) }
    }

    /// The only path that should zero daily balances.
    public func closeOutDay() throws -> Result<Void, CloseOutError> {
        try applyEngine { RulesEngine.closeOutDay($0, at: $1) }
    }

    // MARK: - Diff & save

    private func writeBack(old: HouseholdState, new: HouseholdState) throws {
        try writeBackKids(old: old.kids, new: new.kids)
        try writeBackInstances(old: old.instances, new: new.instances)
        try writeBackAppendOnlyEvents(old: old.events, new: new.events)
        try writeBackAppendOnlyRedemptions(old: old.redemptions, new: new.redemptions)
        try context.save()
    }

    private func writeBackKids(old: [KidSnapshot], new: [KidSnapshot]) throws {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let models = try context.fetch(FetchDescriptor<Kid>())
        let modelsByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        for snapshot in new {
            guard let model = modelsByID[snapshot.id],
                  let oldSnap = oldByID[snapshot.id],
                  oldSnap != snapshot else { continue }
            model.currentDailyBalance = snapshot.currentDailyBalance
        }
    }

    private func writeBackInstances(old: [ChoreInstanceSnapshot],
                                    new: [ChoreInstanceSnapshot]) throws {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newIDs = Set(new.map(\.id))
        let models = try context.fetch(FetchDescriptor<ChoreInstance>())
        let modelsByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        // Deletions first (e.g. closeOutDay sweep)
        for (id, model) in modelsByID where !newIDs.contains(id) && oldByID[id] != nil {
            context.delete(model)
        }
        // Updates
        for snapshot in new {
            guard let model = modelsByID[snapshot.id],
                  let oldSnap = oldByID[snapshot.id],
                  oldSnap != snapshot else { continue }
            model.status = snapshot.status
            model.completedAt = snapshot.completedAt
        }
    }

    private func writeBackAppendOnlyEvents(old: [EventSnapshot], new: [EventSnapshot]) throws {
        let oldIDs = Set(old.map(\.id))
        for snapshot in new where !oldIDs.contains(snapshot.id) {
            context.insert(Event(snapshot: snapshot))
        }
    }

    private func writeBackAppendOnlyRedemptions(old: [RewardRedemptionSnapshot],
                                                new: [RewardRedemptionSnapshot]) throws {
        let oldIDs = Set(old.map(\.id))
        for snapshot in new where !oldIDs.contains(snapshot.id) {
            context.insert(RewardRedemption(snapshot: snapshot))
        }
    }
}

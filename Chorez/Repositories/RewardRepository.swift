import Foundation
import SwiftData

/// CRUD wrapper over `Reward` rows.
///
/// Redemption itself goes through `HouseholdRepository.redeemReward`
/// (per DRY rule "only `redeemReward` debits balance for a redemption")
/// — this repo only manages the catalog. Every mutating call pushes
/// the resulting snapshot (or a tombstone) through the optional sync
/// engine so cross-account replication picks it up.
@MainActor
public final class RewardRepository {
    private let context: ModelContext
    private let syncEngine: (any SharedZoneSyncEngine)?

    public init(context: ModelContext,
                syncEngine: (any SharedZoneSyncEngine)? = nil) {
        self.context = context
        self.syncEngine = syncEngine
    }

    public func all() throws -> [Reward] {
        let descriptor = FetchDescriptor<Reward>(
            sortBy: [SortDescriptor(\.points), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func active() throws -> [Reward] {
        let descriptor = FetchDescriptor<Reward>(
            predicate: #Predicate { $0.active },
            sortBy: [SortDescriptor(\.points), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func find(id: UUID) throws -> Reward? {
        let predicate = #Predicate<Reward> { $0.id == id }
        var descriptor = FetchDescriptor<Reward>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func create(householdID: UUID, name: String, points: Int) throws -> Reward {
        // `Reward.init` defaults `updatedAt = .now`, so the row is
        // sync-ready out of the gate.
        let reward = Reward(householdID: householdID, name: name, points: points)
        context.insert(reward)
        try context.save()
        push(.upsert(reward.snapshot))
        return reward
    }

    public func update(_ reward: Reward,
                       name: String? = nil,
                       points: Int? = nil,
                       active: Bool? = nil) throws {
        if let name { reward.name = name }
        if let points { reward.points = points }
        if let active { reward.active = active }
        // Stamp on every mutation so the sync engine's LWW resolver
        // promotes this edit over any concurrent device's stale copy.
        reward.updatedAt = .now
        try context.save()
        push(.upsert(reward.snapshot))
    }

    /// Hard delete. Past `RewardRedemption` rows keep their captured
    /// `points` value, so historical reads stay correct even after the
    /// catalog entry is gone.
    public func delete(_ reward: Reward) throws {
        let rewardID = reward.id
        context.delete(reward)
        try context.save()
        push(.delete(.init(id: rewardID, ckRecordType: RewardSnapshot.ckRecordType)))
    }

    private func push(_ change: ShareableChange) {
        guard let syncEngine else { return }
        Task { await syncEngine.enqueue(change) }
    }
}

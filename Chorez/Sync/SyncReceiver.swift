import CloudKit
import Foundation
import SwiftData
import os

/// Applies inbound CloudKit changes from `SharedZoneSyncEngine` into the
/// local SwiftData store, with last-writer-wins conflict resolution by
/// `updatedAt`.
///
/// **Loop avoidance**: the receiver writes via direct `ModelContext`
/// access instead of going through `*Repository` methods. Repositories
/// own the outbound `enqueue` calls; routing inbound writes through
/// them would re-broadcast every remote change as a fresh outbound,
/// echoing forever between devices.
///
/// **LWW semantics**: each inbound snapshot carries an `updatedAt`
/// stamped by the originating device. If the local row is newer, the
/// inbound write is dropped silently — that's the right answer when a
/// participant's stale edit arrives after the owner's newer edit, and
/// vice versa.
///
/// **Initial sync**: when a participant first joins a share, the
/// engine fetches the entire shared zone. Each fetched record either
/// inserts a new local row or LWW-updates an existing one, so a fresh
/// participant ends up with the owner's full dataset without any
/// special-case bootstrapping.
@available(iOS 17.5, *)
@MainActor
public final class SyncReceiver {
    private let context: ModelContext
    private let syncEngine: any SharedZoneSyncEngine
    private var task: Task<Void, Never>?
    private let log: Logger

    public init(context: ModelContext, syncEngine: any SharedZoneSyncEngine) {
        self.context = context
        self.syncEngine = syncEngine
        self.log = Logger(subsystem: "com.glarsen.chorez", category: "SyncReceiver")
    }

    /// Subscribe to the engine's inbound stream and start applying
    /// changes. Idempotent — a second call is a no-op so views can
    /// invoke it from `.task { }` without coordination.
    public func start() {
        guard task == nil else { return }
        let stream = syncEngine.inboundChanges()
        task = Task { @MainActor [weak self] in
            for await change in stream {
                self?.apply(change)
            }
        }
    }

    /// Tear down the subscription. Called from scene-leaving teardown
    /// paths if/when we add them; currently unused but exposed for
    /// symmetry and future tests.
    public func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Dispatch

    private func apply(_ change: InboundChange) {
        switch change {
        case .upsertedRecord(let record):
            print("[ReceiverDebug] upsert recordType=\(record.recordType) recordName=\(record.recordID.recordName)")
            for key in record.allKeys() {
                print("[ReceiverDebug]   \(key)=\(String(describing: record[key]))")
            }
            applyUpsert(record)
        case .deletedRecord(let recordID, let recordType):
            print("[ReceiverDebug] delete recordType=\(recordType) recordName=\(recordID.recordName)")
            applyDelete(recordID: recordID, recordType: recordType)
        }
        // Save after each individual change rather than batching — the
        // engine emits events one at a time and we'd rather take the
        // small cost of N saves than risk an unhandled exception
        // mid-batch leaving the store partially updated.
        do {
            try context.save()
        } catch {
            log.error("SwiftData save failed in receiver: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyUpsert(_ record: CKRecord) {
        // Switch only — each branch delegates to a tiny per-type
        // helper so the cyclomatic complexity stays inside the lint
        // cap (the previous in-line `if let snapshot = …` pattern
        // counted every branch twice).
        switch record.recordType {
        case HouseholdSnapshot.ckRecordType: tryApplyHouseholdUpsert(record)
        case KidSnapshot.ckRecordType: tryApplyKidUpsert(record)
        case ChoreTemplateSnapshot.ckRecordType: tryApplyTemplateUpsert(record)
        case ChoreInstanceSnapshot.ckRecordType: tryApplyInstanceUpsert(record)
        case RewardSnapshot.ckRecordType: tryApplyRewardUpsert(record)
        case RewardRedemptionSnapshot.ckRecordType: tryApplyRedemptionUpsert(record)
        case EventSnapshot.ckRecordType: tryApplyEventUpsert(record)
        default:
            log.notice("Ignoring unknown record type: \(record.recordType, privacy: .public)")
        }
    }

    private func tryApplyHouseholdUpsert(_ record: CKRecord) {
        guard let snapshot = HouseholdSnapshot(record: record) else { return }
        upsertHousehold(snapshot)
    }

    private func tryApplyKidUpsert(_ record: CKRecord) {
        guard let snapshot = KidSnapshot(record: record) else { return }
        upsertKid(snapshot)
    }

    private func tryApplyTemplateUpsert(_ record: CKRecord) {
        guard let snapshot = ChoreTemplateSnapshot(record: record) else { return }
        upsertTemplate(snapshot)
    }

    private func tryApplyInstanceUpsert(_ record: CKRecord) {
        guard let snapshot = ChoreInstanceSnapshot(record: record) else { return }
        upsertInstance(snapshot)
    }

    private func tryApplyRewardUpsert(_ record: CKRecord) {
        guard let snapshot = RewardSnapshot(record: record) else { return }
        upsertReward(snapshot)
    }

    private func tryApplyRedemptionUpsert(_ record: CKRecord) {
        guard let snapshot = RewardRedemptionSnapshot(record: record) else { return }
        upsertRedemption(snapshot)
    }

    private func tryApplyEventUpsert(_ record: CKRecord) {
        guard let snapshot = EventSnapshot(record: record) else { return }
        upsertEvent(snapshot)
    }

    private func applyDelete(recordID: CKRecord.ID, recordType: CKRecord.RecordType) {
        // Record names are `"<Type>-<UUID.uuidString>"`. Split on the
        // first `-` because `RecordType` strings never contain dashes
        // (they're Swift type names) and UUID strings always do.
        let parts = recordID.recordName.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let uuid = UUID(uuidString: String(parts[1])) else {
            log.notice("Ignoring unparseable record id: \(recordID.recordName, privacy: .public)")
            return
        }
        switch recordType {
        case HouseholdSnapshot.ckRecordType: deleteHousehold(id: uuid)
        case KidSnapshot.ckRecordType: deleteKid(id: uuid)
        case ChoreTemplateSnapshot.ckRecordType: deleteTemplate(id: uuid)
        case ChoreInstanceSnapshot.ckRecordType: deleteInstance(id: uuid)
        case RewardSnapshot.ckRecordType: deleteReward(id: uuid)
        case RewardRedemptionSnapshot.ckRecordType: deleteRedemption(id: uuid)
        case EventSnapshot.ckRecordType: deleteEvent(id: uuid)
        default:
            log.notice("Ignoring delete for unknown record type: \(recordType, privacy: .public)")
        }
    }

    // MARK: - Upsert per entity (LWW)

    private func upsertHousehold(_ snapshot: HouseholdSnapshot) {
        if let existing = try? fetchOne(Household.self, id: snapshot.id) {
            guard snapshot.updatedAt > existing.updatedAt else { return }
            existing.name = snapshot.name
            existing.ownerCloudUserID = snapshot.ownerCloudUserID
            existing.createdAt = snapshot.createdAt
            existing.lastAutoFillDate = snapshot.lastAutoFillDate
            existing.updatedAt = snapshot.updatedAt
        } else {
            context.insert(Household(snapshot: snapshot))
        }
    }

    private func upsertKid(_ snapshot: KidSnapshot) {
        if let existing = try? fetchOne(Kid.self, id: snapshot.id) {
            guard snapshot.updatedAt > existing.updatedAt else { return }
            existing.householdID = snapshot.householdID
            existing.name = snapshot.name
            existing.displayOrder = snapshot.displayOrder
            existing.currentDailyBalance = snapshot.currentDailyBalance
            existing.updatedAt = snapshot.updatedAt
        } else {
            context.insert(Kid(snapshot: snapshot))
        }
    }

    private func upsertTemplate(_ snapshot: ChoreTemplateSnapshot) {
        if let existing = try? fetchOne(ChoreTemplate.self, id: snapshot.id) {
            guard snapshot.updatedAt > existing.updatedAt else { return }
            existing.householdID = snapshot.householdID
            existing.name = snapshot.name
            existing.points = snapshot.points
            existing.assignedKidID = snapshot.assignedKidID
            existing.recurrence = snapshot.recurrence
            existing.active = snapshot.active
            existing.updatedAt = snapshot.updatedAt
        } else {
            context.insert(ChoreTemplate(snapshot: snapshot))
        }
    }

    private func upsertInstance(_ snapshot: ChoreInstanceSnapshot) {
        if let existing = try? fetchOne(ChoreInstance.self, id: snapshot.id) {
            guard snapshot.updatedAt > existing.updatedAt else { return }
            existing.templateID = snapshot.templateID
            existing.householdID = snapshot.householdID
            existing.name = snapshot.name
            existing.points = snapshot.points
            existing.assignedKidID = snapshot.assignedKidID
            existing.date = snapshot.date
            existing.status = snapshot.status
            existing.completedAt = snapshot.completedAt
            existing.updatedAt = snapshot.updatedAt
        } else {
            context.insert(ChoreInstance(snapshot: snapshot))
        }
    }

    private func upsertReward(_ snapshot: RewardSnapshot) {
        if let existing = try? fetchOne(Reward.self, id: snapshot.id) {
            guard snapshot.updatedAt > existing.updatedAt else { return }
            existing.householdID = snapshot.householdID
            existing.name = snapshot.name
            existing.points = snapshot.points
            existing.active = snapshot.active
            existing.updatedAt = snapshot.updatedAt
        } else {
            context.insert(Reward(snapshot: snapshot))
        }
    }

    private func upsertRedemption(_ snapshot: RewardRedemptionSnapshot) {
        // Append-only — a redemption row only ever gets inserted, never
        // updated. If it's already local, leave it alone; LWW comparison
        // would otherwise treat identical inbound rows as no-ops anyway.
        guard (try? fetchOne(RewardRedemption.self, id: snapshot.id)) == nil else { return }
        context.insert(RewardRedemption(snapshot: snapshot))
    }

    private func upsertEvent(_ snapshot: EventSnapshot) {
        // Append-only like redemptions; no overwrites.
        guard (try? fetchOne(Event.self, id: snapshot.id)) == nil else { return }
        context.insert(Event(snapshot: snapshot))
    }

    // MARK: - Delete per entity

    private func deleteHousehold(id: UUID) {
        guard let model = try? fetchOne(Household.self, id: id) else { return }
        context.delete(model)
    }

    private func deleteKid(id: UUID) {
        guard let model = try? fetchOne(Kid.self, id: id) else { return }
        context.delete(model)
    }

    private func deleteTemplate(id: UUID) {
        guard let model = try? fetchOne(ChoreTemplate.self, id: id) else { return }
        context.delete(model)
    }

    private func deleteInstance(id: UUID) {
        guard let model = try? fetchOne(ChoreInstance.self, id: id) else { return }
        context.delete(model)
    }

    private func deleteReward(id: UUID) {
        guard let model = try? fetchOne(Reward.self, id: id) else { return }
        context.delete(model)
    }

    private func deleteRedemption(id: UUID) {
        guard let model = try? fetchOne(RewardRedemption.self, id: id) else { return }
        context.delete(model)
    }

    private func deleteEvent(id: UUID) {
        guard let model = try? fetchOne(Event.self, id: id) else { return }
        context.delete(model)
    }

    // MARK: - Shared fetch helper

    /// Fetch the single row matching `id` for the given `@Model` type.
    /// Returns nil if not present. Generic over `T` so each per-type
    /// helper can stay a one-liner.
    private func fetchOne<T: PersistentModel & SyncableByID>(_ type: T.Type, id: UUID) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: T.predicate(for: id))
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// Tiny shim so `SyncReceiver.fetchOne` can build a per-type
/// `#Predicate` without conditional compilation per model. Every
/// `@Model` exposes an `id: UUID`, so each conformance is a one-liner.
public protocol SyncableByID {
    static func predicate(for id: UUID) -> Predicate<Self>
}

extension Household: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<Household> {
        #Predicate { $0.id == id }
    }
}

extension Kid: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<Kid> {
        #Predicate { $0.id == id }
    }
}

extension ChoreTemplate: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<ChoreTemplate> {
        #Predicate { $0.id == id }
    }
}

extension ChoreInstance: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<ChoreInstance> {
        #Predicate { $0.id == id }
    }
}

extension Reward: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<Reward> {
        #Predicate { $0.id == id }
    }
}

extension RewardRedemption: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<RewardRedemption> {
        #Predicate { $0.id == id }
    }
}

extension Event: SyncableByID {
    public static func predicate(for id: UUID) -> Predicate<Event> {
        #Predicate { $0.id == id }
    }
}

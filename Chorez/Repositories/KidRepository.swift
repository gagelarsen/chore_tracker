import Foundation
import SwiftData

/// CRUD wrapper over `Kid` rows.
///
/// View models call this repository instead of touching `ModelContext`
/// directly (per `00-standards.md` persistence DRY rule). `currentDailyBalance`
/// is read here for display but only mutated via
/// `HouseholdRepository.applyEngine` — repository updates limited to
/// `name` and `displayOrder` to keep the engine the sole authority on
/// point math.
///
/// Phase 1.5: every mutating method also enqueues the resulting
/// snapshot (or a tombstone) with the optional `syncEngine` so
/// cross-account replication picks the change up on the next batch.
@MainActor
public final class KidRepository {
    private let context: ModelContext
    private let syncEngine: (any SharedZoneSyncEngine)?

    public init(context: ModelContext,
                syncEngine: (any SharedZoneSyncEngine)? = nil) {
        self.context = context
        self.syncEngine = syncEngine
    }

    public func all() throws -> [Kid] {
        let descriptor = FetchDescriptor<Kid>(
            sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    public func find(id: UUID) throws -> Kid? {
        let predicate = #Predicate<Kid> { $0.id == id }
        var descriptor = FetchDescriptor<Kid>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func create(householdID: UUID, name: String, displayOrder: Int? = nil) throws -> Kid {
        let order = try displayOrder ?? all().count
        // `Kid.init` defaults `updatedAt = .now`, so newly created rows
        // are sync-ready without an explicit stamp here.
        let kid = Kid(householdID: householdID, name: name, displayOrder: order)
        context.insert(kid)
        try context.save()
        push(.upsert(kid.snapshot))
        return kid
    }

    public func rename(_ kid: Kid, to newName: String) throws {
        kid.name = newName
        // Stamp on every mutation so the sync engine's LWW resolver
        // promotes this edit over any concurrent device's stale copy.
        kid.updatedAt = .now
        try context.save()
        push(.upsert(kid.snapshot))
    }

    public func reorder(_ kid: Kid, to displayOrder: Int) throws {
        kid.displayOrder = displayOrder
        kid.updatedAt = .now
        try context.save()
        push(.upsert(kid.snapshot))
    }

    /// Hard delete with cascade to children the kid owns directly.
    ///
    /// Deletes the `Kid`, every `ChoreTemplate` assigned to them
    /// (templates are personalized in v1), every pending `ChoreInstance`
    /// regardless of date, and every future `ChoreInstance` (status
    /// irrelevant). **Completed instances on today or earlier stay** so
    /// the audit query against `Event` records is still
    /// self-consistent — every `choreCompleted` event still has its
    /// referenced `ChoreInstance` row. Append-only `Event` and
    /// `RewardRedemption` rows are never touched.
    public func delete(_ kid: Kid) throws {
        let kidID = kid.id
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)

        // Capture cascade victims before deletion so we can broadcast
        // tombstones for them. CloudKit's shared zone has no
        // automatic foreign-key cascade — every deletion has to ride
        // out explicitly.
        let cascadingTemplates = try context.fetch(
            FetchDescriptor<ChoreTemplate>(
                predicate: #Predicate { $0.assignedKidID == kidID }
            )
        )
        let cascadingInstances = try context.fetch(
            FetchDescriptor<ChoreInstance>(
                predicate: #Predicate { instance in
                    instance.assignedKidID == kidID
                    && (instance.statusRaw == "pending" || instance.date > today)
                }
            )
        )

        try context.delete(model: ChoreTemplate.self,
                           where: #Predicate { $0.assignedKidID == kidID })
        // `instance.date > today` (strictly greater): future instances
        // are wiped regardless of status, but completed-today instances
        // stay so the audit log isn't orphaned. Pending instances
        // (any date, past or today) are also wiped — nothing left for
        // the kid to do.
        try context.delete(model: ChoreInstance.self,
                           where: #Predicate { instance in
                               instance.assignedKidID == kidID
                               && (instance.statusRaw == "pending" || instance.date > today)
                           })
        context.delete(kid)
        try context.save()

        push(.delete(.init(id: kidID, ckRecordType: KidSnapshot.ckRecordType)))
        for template in cascadingTemplates {
            push(.delete(.init(id: template.id, ckRecordType: ChoreTemplateSnapshot.ckRecordType)))
        }
        for instance in cascadingInstances {
            push(.delete(.init(id: instance.id, ckRecordType: ChoreInstanceSnapshot.ckRecordType)))
        }
    }

    private func push(_ change: ShareableChange) {
        guard let syncEngine else { return }
        // Fire-and-forget: enqueue is just dict mutation on the
        // main actor; the actual CloudKit round-trip is batched by
        // the engine asynchronously.
        Task { await syncEngine.enqueue(change) }
    }
}

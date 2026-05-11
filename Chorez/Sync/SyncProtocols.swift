import CloudKit
import Foundation

/// Shared contract for Phase 1.5's two-account replication. Agents A
/// (foundation) and B (sync engine) work against these protocols so
/// each piece is independently implementable.
///
/// Conventions baked in here:
/// - **LWW conflict resolution** via `updatedAt`. Every mutation that
///   needs to replicate stamps `updatedAt = now`. On inbound writes,
///   the resolver keeps whichever side has the newer timestamp.
/// - **Single shared zone** named `Self.sharedZoneName`. All
///   sync-eligible records live there so one `CKShare` rooted on the
///   zone covers every entity.
/// - **CKRecord-type-per-@Model**. Names are stable (mirroring SwiftData's
///   `@Model` type name) so a schema rename triggers a CloudKit migration
///   intentionally rather than silently desyncing.

/// Snapshot type that can survive a round-trip through CloudKit.
///
/// Implementing types are the value-type snapshots from
/// `Chorez/Domain/` (KidSnapshot, ChoreInstanceSnapshot, …), not the
/// `@Model` classes — the sync layer trades exclusively in pure values
/// to keep CloudKit calls off the SwiftData actor.
public protocol ShareableRecord: Hashable, Sendable {
    /// Stable record name across both ends of the share. Always a UUID
    /// matching the corresponding SwiftData row's `id`.
    var id: UUID { get }

    /// LWW arbiter. Every mutation path stamps this with `now` before
    /// queueing the change. Conflict resolution keeps the snapshot
    /// with the larger `updatedAt`.
    var updatedAt: Date { get set }

    /// CloudKit record type. Stable; renames are migrations.
    static var ckRecordType: String { get }

    /// Encode every field into the `CKRecord`'s key-value store. The
    /// record's `recordID.recordName` is already populated by the
    /// caller, so implementations should not assign a `recordID`.
    func encode(into record: CKRecord)

    /// Decode a `CKRecord` back into the snapshot. Returns `nil` if
    /// any required field is missing or malformed — sync layer treats
    /// nil as "record is on the way / corrupt; skip this batch".
    init?(record: CKRecord)
}

/// Identifies a deleted record across the sync boundary. CloudKit uses
/// `CKRecord.ID`; SwiftData uses `UUID`. Sync layer carries both.
public struct ShareableRecordTombstone: Hashable, Sendable {
    public let id: UUID
    public let ckRecordType: String

    public init(id: UUID, ckRecordType: String) {
        self.id = id
        self.ckRecordType = ckRecordType
    }
}

/// Outbound change queued for CloudKit. `upsert` carries the full
/// snapshot (so the sync engine can encode at flush time); `delete`
/// carries just enough to issue a `CKModifyRecordsOperation` deletion.
public enum ShareableChange: Hashable, Sendable {
    case upsert(any ShareableRecord)
    case delete(ShareableRecordTombstone)

    public static func == (lhs: ShareableChange, rhs: ShareableChange) -> Bool {
        switch (lhs, rhs) {
        case let (.upsert(left), .upsert(right)):
            return AnyHashable(left) == AnyHashable(right)
        case let (.delete(left), .delete(right)):
            return left == right
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .upsert(let record):
            hasher.combine("upsert")
            hasher.combine(AnyHashable(record))
        case .delete(let tombstone):
            hasher.combine("delete")
            hasher.combine(tombstone)
        }
    }
}

/// Inbound change pulled from CloudKit. Agent B (the sync engine)
/// emits these to the integration layer, which dispatches to the
/// appropriate repository.
public enum InboundChange: Sendable {
    case upsertedRecord(CKRecord)
    case deletedRecord(recordID: CKRecord.ID, recordType: CKRecord.RecordType)
}

/// Sync engine surface used by repositories and the integration layer.
/// Agent B implements this against `CKSyncEngine`.
public protocol SharedZoneSyncEngine: AnyObject, Sendable {
    /// Queue an outbound change. Returns immediately; actual CloudKit
    /// write batches by the engine's heuristics. Idempotent against
    /// `id` — a second upsert overwrites the first in the queue.
    func enqueue(_ change: ShareableChange) async

    /// `AsyncStream` of inbound changes pulled from the shared zone.
    /// One stream per process; multiple subscribers each get their own
    /// stream via the conformance.
    func inboundChanges() -> AsyncStream<InboundChange>

    /// Force a sync now (e.g. after share acceptance). Returns when
    /// the next batch round-trip completes.
    func syncNow() async throws

    /// Names used by both the share coordinator and the engine.
    static var sharedZoneName: String { get }
}

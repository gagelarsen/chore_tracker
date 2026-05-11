import CloudKit
import Foundation
import os

/// Thin `CKSyncEngine` wrapper that satisfies `SharedZoneSyncEngine`.
///
/// Why a wrapper rather than exposing `CKSyncEngine` directly: the
/// integration layer should not know whether sync is backed by
/// `CKSyncEngine`, a hand-rolled `CKModifyRecordsOperation` loop, or a
/// mock. `SharedZoneSyncEngine` is the seam — this class implements it
/// using Apple's iOS 17+ engine so we get change tracking, retry,
/// subscription wake-up, and zone management for free.
///
/// Threading: `@MainActor` so callers can safely interact from SwiftUI
/// without bouncing actors. `CKSyncEngine`'s delegate callbacks are
/// already async, and we re-enter the main actor inside them to mutate
/// the queue dictionaries. The CKSyncEngine itself does its CloudKit
/// work on its own task queue — we never block the main actor on a
/// CloudKit round-trip.
@available(iOS 17.5, *)
@MainActor
public final class CKSyncEngineCoordinator: SharedZoneSyncEngine {
    /// Proxy to `SharedZone.name`. Exposed as the protocol witness so
    /// callers that hold a `SharedZoneSyncEngine` reference can read
    /// the zone name without importing the `SharedZone` namespace.
    public nonisolated static let sharedZoneName = SharedZone.name

    /// `UserDefaults` key persisted by `acceptShareInvitation(_:)` so
    /// subsequent launches know to point the coordinator at the
    /// shared (participant) database. Cleared on `.accountChange`.
    public static let participantDefaultsKey = "chorez.cksyncengine.isParticipant"

    /// Persisted owner record name from the first shared-zone fetch,
    /// stored so outbound writes carry the right `zoneID.ownerName`
    /// in participant mode. `CKCurrentUserDefaultName` is the right
    /// answer in owner mode (and as a fallback when we haven't yet
    /// observed any shared records).
    internal static let participantOwnerKeyPrefix = "chorez.cksyncengine.ownerRecordName."

    /// Per-batch cap. CloudKit's documented batch ceiling is 400
    /// records; staying well under it keeps round-trips snappy and
    /// avoids the partial-failure paths.
    private static let maxBatchSize = 100

    /// Identifier the engine reports its container as. Kept as a
    /// stored property so the `UserDefaults` state key stays stable
    /// across re-inits with the same identifier, and so the
    /// `CKContainer` can be constructed lazily inside `start()`.
    ///
    /// Why lazy: in CI / simulator builds with
    /// `CODE_SIGNING_ALLOWED=NO`, the iCloud entitlement is stripped
    /// and `CKContainer(identifier:)` aborts the process. By
    /// deferring the container until the caller actually starts the
    /// engine, plain `init()` stays safe for unit-test fixtures that
    /// never call `start()`.
    internal let containerIdentifier: String

    /// Role the coordinator runs in. Determines whether
    /// `CKSyncEngine` reads from the private or shared CloudKit
    /// database. Persisted by `acceptShareInvitation(_:)` so a
    /// relaunch keeps the right role automatically.
    internal let role: CKSyncEngineRole

    /// Cached `ownerName` for the shared zone. `nil` until the first
    /// inbound record arrives (participant mode) — owner mode always
    /// uses `CKCurrentUserDefaultName`.
    internal var sharedZoneOwnerName: String?

    /// Lazily-built CloudKit container. Populated on first `start()`.
    private var container: CKContainer?

    /// Engine instance. Optional because `start()` is what actually
    /// constructs it (subscription registration + first sync). Once
    /// set, never reassigned for the lifetime of this coordinator.
    private var engine: CKSyncEngine?

    /// Tracks whether `start()` has already run so a second call is a
    /// safe no-op (per the protocol's idempotency requirement).
    private var hasStarted = false

    /// Pending upserts keyed by `CKRecord.ID`. Last write wins —
    /// re-enqueuing the same id replaces the previous snapshot.
    private var pendingUpserts: [CKRecord.ID: any ShareableRecord] = [:]

    /// Pending deletes. Stored as a set because deletes are
    /// idempotent and carry no payload. When a delete is enqueued
    /// for an id that also has a pending upsert, the upsert is
    /// dropped — a delete always wins to avoid resurrecting a row
    /// that the user just removed.
    private var pendingDeletes: Set<CKRecord.ID> = []

    /// Inbound stream fan-out. Each call to `inboundChanges()` mints
    /// a fresh stream and stashes its continuation here so delegate
    /// events broadcast to every active subscriber. Keyed by UUID so
    /// `onTermination` can remove cancelled streams without scanning.
    ///
    /// Wrapped in `os_unfair_lock` rather than gated solely by the
    /// main actor because `inboundChanges()` is a `nonisolated`
    /// protocol witness — it must be safe to call from any actor
    /// context. Reading/writing the dictionary itself is trivially
    /// cheap so the lock cost is negligible.
    private let continuationLock = OSAllocatedUnfairLock<
        [UUID: AsyncStream<InboundChange>.Continuation]
    >(initialState: [:])

    /// `os.Logger` for sync-flow visibility. Sync issues are
    /// notoriously hard to reproduce after the fact, so we leave
    /// breadcrumbs at every lifecycle event without bloating signpost
    /// budget the way `print` would.
    internal let log: Logger

    /// Build a coordinator for the given CloudKit container. The
    /// CloudKit container itself is materialised lazily in `start()`
    /// — `init` never touches CloudKit so it's safe to construct in
    /// environments where the iCloud entitlement isn't present (CI
    /// simulator builds with `CODE_SIGNING_ALLOWED=NO`, unit tests
    /// that never call `start()`).
    ///
    /// `role` defaults to whatever the participant flag in
    /// `UserDefaults` says — set by `acceptShareInvitation(_:)` after
    /// the spouse joins. Override the parameter in tests to drive
    /// either role deterministically.
    public init(containerIdentifier: String,
                role: CKSyncEngineRole = CKSyncEngineCoordinator.persistedRole()) {
        self.containerIdentifier = containerIdentifier
        self.role = role
        self.log = Logger(subsystem: "com.glarsen.chorez", category: "CKSyncEngine")
        // Load any persisted owner record name so the first batch
        // can already point participant-side writes at the right
        // zone without waiting for an inbound record.
        let ownerKey = Self.participantOwnerKeyPrefix + containerIdentifier
        self.sharedZoneOwnerName = UserDefaults.standard.string(forKey: ownerKey)
    }

    /// Spin up the engine, register the zone subscription, ensure the
    /// shared zone exists, and request a first sync. Idempotent — a
    /// second invocation is a no-op so views can safely call
    /// `start()` from `.task { }` without coordination.
    public func start() async throws {
        guard !hasStarted else { return }
        hasStarted = true

        let liveContainer = CKContainer(identifier: containerIdentifier)
        container = liveContainer

        let database: CKDatabase = role == .owner
            ? liveContainer.privateCloudDatabase
            : liveContainer.sharedCloudDatabase

        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadState(),
            delegate: self
        )
        let newEngine = CKSyncEngine(configuration)
        engine = newEngine

        if role == .owner {
            // Owner mints the zone. Participants must not — the zone
            // is owned by the inviter and the participant's database
            // doesn't accept `saveZone` on a zone the user doesn't
            // own. CKSyncEngine handles "the zone already exists"
            // silently for the owner case.
            let zoneID = sharedZoneIDForCurrentRole()
            newEngine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: zoneID))
            ])
        }

        // Re-register any queue items that callers `enqueue`d before
        // `start()` ran. Without this, the engine wouldn't know it
        // has record-zone work pending and `nextRecordZoneChangeBatch`
        // would never be called for that backlog.
        var preStartPending: [CKSyncEngine.PendingRecordZoneChange] = []
        preStartPending.reserveCapacity(pendingUpserts.count + pendingDeletes.count)
        preStartPending.append(contentsOf: pendingUpserts.keys.map { .saveRecord($0) })
        preStartPending.append(contentsOf: pendingDeletes.map { .deleteRecord($0) })
        if !preStartPending.isEmpty {
            newEngine.state.add(pendingRecordZoneChanges: preStartPending)
        }

        if role == .owner {
            // Subscription registration is for the owner side only;
            // CloudKit auto-subscribes participants to their shared
            // zones, so a duplicate subscription on the participant
            // side would error.
            try await ensureZoneSubscription(zoneID: sharedZoneIDForCurrentRole())
        }

        // Kick off the first round-trip so the zone + subscription
        // land server-side before the integration layer starts
        // queueing real data.
        try await newEngine.sendChanges()
        try await newEngine.fetchChanges()
        let identifier = self.containerIdentifier
        let roleName = String(describing: self.role)
        log.info("CKSyncEngine started container=\(identifier, privacy: .public) role=\(roleName, privacy: .public)")
    }

    /// Idempotent zone-subscription save. We do this through the
    /// database (not the engine) because CloudKit's `CKSyncEngine`
    /// only tracks zone create/delete in its database-change pending
    /// list — subscriptions are out-of-band. Treating a "subscription
    /// already exists" rejection as success means a relaunch on the
    /// same install doesn't error out.
    private func ensureZoneSubscription(zoneID: CKRecordZone.ID) async throws {
        guard let container else { return }
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: SharedZone.subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        // Silent push: no alert, no badge, no sound. CloudKit just
        // wakes the app long enough for the engine to fetch.
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await container.privateCloudDatabase.modifySubscriptions(
                saving: [subscription],
                deleting: []
            )
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Server rejected because the subscription already
            // exists — that's the success case for our idempotency.
            log.debug("Zone subscription already registered (server rejected duplicate)")
        }
    }

    // MARK: - SharedZoneSyncEngine

    /// Queue an outbound change. Returns immediately; the engine
    /// decides when to flush. Re-enqueuing the same id replaces the
    /// prior snapshot; enqueuing a delete after an upsert drops the
    /// upsert (delete-overrides-upsert keeps a just-deleted row from
    /// resurrecting if both arrive in the same batch window).
    public func enqueue(_ change: ShareableChange) async {
        switch change {
        case .upsert(let record):
            let recordID = recordID(for: record.id, recordType: type(of: record).ckRecordType)
            // Drop a stale delete if the caller re-creates the row.
            pendingDeletes.remove(recordID)
            pendingUpserts[recordID] = record
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .delete(let tombstone):
            let recordID = recordID(for: tombstone.id, recordType: tombstone.ckRecordType)
            pendingUpserts[recordID] = nil
            pendingDeletes.insert(recordID)
            engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        }
    }

    /// Returns a fresh inbound stream. Each subscriber gets its own
    /// stream so the integration layer can run multiple consumers
    /// (e.g. a repository dispatcher + a debug logger) without one
    /// starving the other.
    ///
    /// `nonisolated` because the protocol witness is non-isolated;
    /// all dictionary mutation goes through `continuationLock` so
    /// it's safe from any actor context.
    public nonisolated func inboundChanges() -> AsyncStream<InboundChange> {
        let id = UUID()
        return AsyncStream { continuation in
            continuationLock.withLock { $0[id] = continuation }
            // `onTermination` fires for both consumer-side cancel and
            // continuation-side finish, so this single hook keeps
            // the dictionary from leaking continuations.
            continuation.onTermination = { [continuationLock] _ in
                continuationLock.withLock { $0[id] = nil }
            }
        }
    }

    /// Force a fetch + send round-trip. Used after share acceptance
    /// (when the participant just gained access to the zone and we
    /// want their first sync to happen now, not on the next push).
    public func syncNow() async throws {
        guard let engine else { return }
        try await engine.fetchChanges()
        try await engine.sendChanges()
    }

    // MARK: - Internal seams (delegate + tests)

    /// Compute a `CKRecord.ID` for a given snapshot id. Shared
    /// helper so the upsert path, the delete path, and the delegate
    /// batch builder all derive the same id from the same inputs.
    ///
    /// Record name is `"<RecordType>-<UUID>"` rather than the bare
    /// UUID so a stray collision between two record types (e.g. a
    /// future migration that re-uses an id) is locally visible
    /// instead of silently overwriting.
    internal func recordID(for id: UUID, recordType: String) -> CKRecord.ID {
        return CKRecord.ID(recordName: "\(recordType)-\(id.uuidString)",
                           zoneID: sharedZoneIDForCurrentRole())
    }

    /// Snapshot of the pending dictionaries for the engine's next
    /// batch. Returns up to `maxBatchSize` items of each kind so the
    /// engine doesn't blow the CloudKit batch ceiling. Internal so
    /// the delegate extension can reach it; not exposed publicly.
    ///
    /// Note: this is a peek, not a drain — actual removal happens in
    /// `clearSent` once the engine reports the batch as sent. That
    /// keeps a transient `nextRecordZoneChangeBatch` call from
    /// dropping records if the engine later decides not to send
    /// them (e.g. network goes down mid-batch).
    internal func peekPendingChanges()
        -> (upserts: [CKRecord.ID: any ShareableRecord], deletes: [CKRecord.ID]) {
        // Dictionary/Set iteration order is unspecified, so when the
        // queue exceeds `maxBatchSize` the slice is non-deterministic.
        // That's fine: the engine calls `nextRecordZoneChangeBatch`
        // repeatedly until our queue empties, and any subset is valid
        // forward progress.
        let upsertSlice = pendingUpserts.prefix(Self.maxBatchSize)
        let deleteSlice = Array(pendingDeletes.prefix(Self.maxBatchSize))
        let upserts = Dictionary(uniqueKeysWithValues: upsertSlice.map { ($0.key, $0.value) })
        return (upserts, deleteSlice)
    }

    /// Remove records the engine has confirmed it sent so a
    /// follow-up batch doesn't re-send them. Called from
    /// `.sentRecordZoneChanges` in the delegate.
    internal func clearSent(savedRecordIDs: [CKRecord.ID], deletedRecordIDs: [CKRecord.ID]) {
        for id in savedRecordIDs {
            pendingUpserts[id] = nil
        }
        for id in deletedRecordIDs {
            pendingDeletes.remove(id)
        }
    }

    /// Broadcast an inbound event to every active subscriber. The
    /// `yield` calls are cheap; an in-flight slow consumer doesn't
    /// block others because `AsyncStream`'s default buffering policy
    /// is unbounded.
    ///
    /// `nonisolated` so the delegate can invoke it without an actor
    /// hop. Continuation map access is guarded by the lock; the
    /// `yield` call itself is documented as thread-safe.
    internal nonisolated func broadcast(_ change: InboundChange) {
        let continuations = continuationLock.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(change)
        }
    }

    /// Test-only seam to drive the inbound stream without spinning
    /// up real CloudKit. Marked `internal` so `@testable import`
    /// can reach it; production code uses the delegate path.
    internal func injectInboundChange(_ change: InboundChange) {
        broadcast(change)
    }

    /// Drop everything still in the outbound queue. Called from
    /// `resetState()` when CloudKit signals an `.accountChange` —
    /// the queued items belong to the signed-out account and can't
    /// be flushed against the new one anyway.
    internal func clearPendingChanges() {
        pendingUpserts.removeAll()
        pendingDeletes.removeAll()
    }
}

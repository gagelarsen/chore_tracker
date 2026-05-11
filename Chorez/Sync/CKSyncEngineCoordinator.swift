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
    /// Single shared zone for every record the household syncs. Must
    /// match `CloudKitShareCoordinator.Coordinator.sharedZoneName` so
    /// the share-root record and the data records live in the same
    /// zone (a `CKShare` covers exactly one zone).
    ///
    /// `nonisolated` so a non-actor-isolated protocol witness can use
    /// it without forcing every caller onto the main actor.
    public nonisolated static let sharedZoneName = "ChorezSharedZone"

    /// `CKRecordZoneSubscription` identifier. Constant so a re-launch
    /// re-uses the existing server-side subscription rather than
    /// piling up duplicates.
    private static let zoneSubscriptionID = "chorez.shared-zone-subscription"

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
    private let containerIdentifier: String

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
    private let log: Logger

    /// Build a coordinator for the given CloudKit container. The
    /// CloudKit container itself is materialised lazily in `start()`
    /// — `init` never touches CloudKit so it's safe to construct in
    /// environments where the iCloud entitlement isn't present (CI
    /// simulator builds with `CODE_SIGNING_ALLOWED=NO`, unit tests
    /// that never call `start()`).
    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
        self.log = Logger(subsystem: "com.glarsen.chorez", category: "CKSyncEngine")
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

        let configuration = CKSyncEngine.Configuration(
            database: liveContainer.privateCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        let newEngine = CKSyncEngine(configuration)
        engine = newEngine

        // Zone create is registered through the engine so its
        // database-change tracking knows about it. `PendingDatabaseChange`
        // only supports `.saveZone` / `.deleteZone` — subscriptions are
        // not part of the enum, so they go through the underlying
        // database below.
        let zoneID = CKRecordZone.ID(zoneName: Self.sharedZoneName,
                                     ownerName: CKCurrentUserDefaultName)
        newEngine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID))
        ])

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

        // Register the zone subscription directly on the private
        // database. CloudKit dedupes by `subscriptionID`, so re-saving
        // the same subscription is a no-op on the server side. We
        // swallow the "already exists" path explicitly because the
        // CloudKit SDK still throws a `.serverRejectedRequest` rather
        // than treating it as success.
        try await ensureZoneSubscription(zoneID: zoneID)

        // Kick off the first round-trip so the zone + subscription
        // land server-side before the integration layer starts
        // queueing real data.
        try await newEngine.sendChanges()
        try await newEngine.fetchChanges()
        log.info("CKSyncEngine started for container \(self.containerIdentifier, privacy: .public)")
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
            subscriptionID: Self.zoneSubscriptionID
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
        let zoneID = CKRecordZone.ID(zoneName: Self.sharedZoneName,
                                     ownerName: CKCurrentUserDefaultName)
        return CKRecord.ID(recordName: "\(recordType)-\(id.uuidString)", zoneID: zoneID)
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

    /// `UserDefaults` key for the persisted CKSyncEngine state blob.
    /// Namespaced by container id so a switch between staging /
    /// production containers doesn't cross-contaminate state.
    private var stateKey: String {
        "chorez.cksyncengine.state.\(containerIdentifier)"
    }

    /// Load the engine's previously persisted state. Falls back to
    /// `nil` on decode failure so a corrupted blob doesn't wedge the
    /// app — the engine treats nil as "fresh install" and re-fetches
    /// the world.
    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            log.error("Failed to decode CKSyncEngine state: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Persist the engine's latest state. Encoded as JSON so it's
    /// inspectable in `defaults read` during debugging; the blob is
    /// small (a few KB) so the choice has no perf cost.
    internal func saveState(_ state: CKSyncEngine.State.Serialization) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            log.error("Failed to encode CKSyncEngine state: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wipe persisted state. Called on `.accountChange` so a
    /// sign-out / sign-in cycle starts from a clean slate rather
    /// than re-applying the previous account's tokens.
    internal func resetState() {
        UserDefaults.standard.removeObject(forKey: stateKey)
        pendingUpserts.removeAll()
        pendingDeletes.removeAll()
    }
}

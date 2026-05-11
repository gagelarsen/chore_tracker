import CloudKit
import Foundation

/// `CKSyncEngineDelegate` conformance.
///
/// Split into its own file so `CKSyncEngineCoordinator.swift` stays
/// under the 400-line cap (per CLAUDE.md style) and the delegate
/// dispatch table reads top-to-bottom without the storage and seam
/// methods in between.
@available(iOS 17.5, *)
extension CKSyncEngineCoordinator: CKSyncEngineDelegate {
    /// Engine event hand-off. The engine drives every state
    /// transition through this method; we route each case to the
    /// matching coordinator helper so the heavy lifting stays out
    /// of the switch statement.
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            saveState(stateUpdate.stateSerialization)
        case .accountChange:
            // Apple's pattern: drop everything and let the engine
            // re-bootstrap. Any in-flight queued change is from the
            // signed-out account and can't be flushed against the
            // new account anyway.
            resetState()
        case .fetchedRecordZoneChanges(let fetched):
            for modification in fetched.modifications {
                captureOwnerName(from: modification.record.recordID)
                broadcast(.upsertedRecord(modification.record))
            }
            for deletion in fetched.deletions {
                captureOwnerName(from: deletion.recordID)
                broadcast(.deletedRecord(
                    recordID: deletion.recordID,
                    recordType: deletion.recordType
                ))
            }
        case .sentRecordZoneChanges(let sent):
            // Clear records the engine successfully sent. Failed
            // sends stay queued so the engine retries them on the
            // next batch (CKSyncEngine's retry policy is opaque but
            // documented as honouring its own backoff).
            let savedIDs = sent.savedRecords.map { $0.recordID }
            let deletedIDs = sent.deletedRecordIDs
            clearSent(savedRecordIDs: savedIDs, deletedRecordIDs: deletedIDs)
        case .willFetchChanges,
             .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges,
             .didFetchChanges,
             .willSendChanges,
             .didSendChanges,
             .fetchedDatabaseChanges,
             .sentDatabaseChanges:
            // Lifecycle pings. The engine emits these around every
            // round-trip; useful for instrumentation but no state
            // change required for Phase 1.5.
            break
        @unknown default:
            // Future SDK adds a new case — log and ignore. The
            // engine's contract says delegates may safely no-op on
            // unknown events.
            break
        }
    }

    /// Build the next outbound batch the engine should send.
    ///
    /// CKSyncEngine asks the delegate for a batch every time it has
    /// `pending*` items it wants to flush. We:
    ///   1. Drain our queue dictionaries (up to `maxBatchSize`).
    ///   2. Hand the resulting record IDs to
    ///      `RecordZoneChangeBatch(pendingChanges:recordProvider:)`,
    ///      which calls our closure once per record ID to ask for
    ///      the populated `CKRecord`.
    ///   3. Encode each pending upsert via `ShareableRecord.encode`.
    ///
    /// Returning `nil` tells the engine "no work" — important so the
    /// engine doesn't burn round-trips when only zone/subscription
    /// changes are pending.
    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let (upserts, deletes) = peekPendingChanges()
        guard !upserts.isEmpty || !deletes.isEmpty else { return nil }

        // Build the pending-change list the engine asked us to
        // batch. We re-build this from our own queue (rather than
        // trusting `context.reason` or `syncEngine.state`) so the
        // delete-overrides-upsert ordering we maintain locally is
        // the one that ships.
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        pending.reserveCapacity(upserts.count + deletes.count)
        for id in upserts.keys {
            pending.append(.saveRecord(id))
        }
        for id in deletes {
            pending.append(.deleteRecord(id))
        }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            // Engine calls back for each `.saveRecord` we listed.
            // Deletes don't hit this closure (the engine handles
            // them by recordID alone), so a missing snapshot here
            // means we listed a record we no longer have — return
            // nil to skip it.
            guard let snapshot = upserts[recordID] else { return nil }
            let recordType = Swift.type(of: snapshot).ckRecordType
            let record = CKRecord(recordType: recordType, recordID: recordID)
            snapshot.encode(into: record)
            return record
        }
    }
}

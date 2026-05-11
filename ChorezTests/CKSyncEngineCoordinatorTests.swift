// CKSyncEngine round-trip with real CloudKit is exercised on real
// hardware only — this suite covers the local queueing, fan-out, and
// state-tracking paths that don't require an iCloud account or a
// signed entitlement.
//
// Each test uses a unique container identifier string so the engine's
// `UserDefaults`-backed state slot is unique per test and prior runs
// don't leak into the next assertion. We never call `start()` so no
// CloudKit traffic is generated — the engine instance stays nil and
// the tests exercise the pure-local queue + fan-out paths.

import CloudKit
import Foundation
import Testing
@testable import Chorez

@MainActor
@Suite("CKSyncEngineCoordinator")
struct CKSyncEngineCoordinatorTests {

    /// Fresh container identifier per test invocation so the
    /// `UserDefaults` state slot is unique across runs and order. The
    /// coordinator never calls `start()` in this suite, so the id
    /// can be synthetic — `CKContainer` is only materialised lazily
    /// inside `start()`.
    private static func uniqueContainerID(_ tag: String) -> String {
        "iCloud.test.chorez.\(tag).\(UUID().uuidString)"
    }

    /// Build a coordinator under a one-shot synthetic container id
    /// and immediately wipe its persisted state. Tests assert against
    /// the in-memory queue + fan-out paths only.
    private static func makeCoordinator(_ tag: String = "default")
        -> CKSyncEngineCoordinator {
        let coordinator = CKSyncEngineCoordinator(
            containerIdentifier: uniqueContainerID(tag)
        )
        coordinator.resetState()
        return coordinator
    }

    @Test("init does not crash for a valid container identifier")
    func initSucceeds() {
        let coordinator = Self.makeCoordinator("init")
        // Construction alone is the assertion: a non-nil result and
        // no thrown error. Read the public zone name back to confirm
        // the instance is usable.
        #expect(type(of: coordinator).sharedZoneName == "ChorezSharedZone")
    }

    @Test("sharedZoneName matches the protocol constant")
    func sharedZoneNameMatchesProtocol() {
        // The `CloudKitShareCoordinator` already hard-codes
        // "ChorezSharedZone" as its share zone — the engine must
        // agree or the share-root record and the data records will
        // live in different zones and never sync.
        #expect(CKSyncEngineCoordinator.sharedZoneName == "ChorezSharedZone")
    }

    @Test("inboundChanges() delivers events to a single subscriber")
    func inboundStreamDelivers() async {
        let coordinator = Self.makeCoordinator("inbound-single")
        let stream = coordinator.inboundChanges()
        let zoneID = CKRecordZone.ID(zoneName: CKSyncEngineCoordinator.sharedZoneName,
                                     ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "K-1", zoneID: zoneID)
        let event = InboundChange.deletedRecord(recordID: recordID, recordType: "Kid")

        // Inject after a brief actor hop so the async iterator is
        // suspended on `next()` when the event arrives — otherwise
        // the `yield` happens before the consumer is listening and
        // the test races.
        Task { @MainActor in
            coordinator.injectInboundChange(event)
        }

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        guard case .deletedRecord(let id, let type) = received else {
            Issue.record("Expected .deletedRecord, got \(String(describing: received))")
            return
        }
        #expect(id == recordID)
        #expect(type == "Kid")
    }

    @Test("delete after upsert results in only the delete being queued")
    func deleteOverridesUpsert() async {
        let coordinator = Self.makeCoordinator("delete-wins")
        let snapshot = TestSnapshot(id: UUID(), updatedAt: Date())
        await coordinator.enqueue(.upsert(snapshot))
        await coordinator.enqueue(.delete(ShareableRecordTombstone(
            id: snapshot.id,
            ckRecordType: TestSnapshot.ckRecordType
        )))

        let (upserts, deletes) = coordinator.peekPendingChanges()
        #expect(upserts.isEmpty, "delete should have removed the prior upsert")
        #expect(deletes.count == 1)
        let expectedID = coordinator.recordID(for: snapshot.id,
                                              recordType: TestSnapshot.ckRecordType)
        #expect(deletes.contains(expectedID))
    }

    @Test("re-enqueueing an upsert for the same id keeps the latest snapshot")
    func upsertLastWriteWins() async {
        let coordinator = Self.makeCoordinator("lww")
        let id = UUID()
        let first = TestSnapshot(id: id, updatedAt: Date(), payload: "v1")
        let second = TestSnapshot(id: id, updatedAt: Date(), payload: "v2")

        await coordinator.enqueue(.upsert(first))
        await coordinator.enqueue(.upsert(second))

        let (upserts, _) = coordinator.peekPendingChanges()
        #expect(upserts.count == 1)
        let expectedID = coordinator.recordID(for: id,
                                              recordType: TestSnapshot.ckRecordType)
        let stored = upserts[expectedID] as? TestSnapshot
        #expect(stored?.payload == "v2", "second enqueue should overwrite first")
    }

    @Test("multiple inboundChanges() subscribers each receive the event")
    func fanOutToMultipleSubscribers() async {
        let coordinator = Self.makeCoordinator("fanout")
        let streamA = coordinator.inboundChanges()
        let streamB = coordinator.inboundChanges()
        let zoneID = CKRecordZone.ID(zoneName: CKSyncEngineCoordinator.sharedZoneName,
                                     ownerName: CKCurrentUserDefaultName)
        let event = InboundChange.deletedRecord(
            recordID: CKRecord.ID(recordName: "K-2", zoneID: zoneID),
            recordType: "Kid"
        )

        Task { @MainActor in
            coordinator.injectInboundChange(event)
        }

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()
        let receivedA = await iteratorA.next()
        let receivedB = await iteratorB.next()

        if case .deletedRecord(_, let typeA) = receivedA {
            #expect(typeA == "Kid")
        } else {
            Issue.record("Subscriber A did not receive the event")
        }
        if case .deletedRecord(_, let typeB) = receivedB {
            #expect(typeB == "Kid")
        } else {
            Issue.record("Subscriber B did not receive the event")
        }
    }
}

// MARK: - Test fixtures

/// Minimal `ShareableRecord` value for queue-behaviour tests. Lives
/// inside the test target so the production code stays free of fake
/// types, and it carries a `payload` field so the LWW test can
/// distinguish v1 from v2 without relying on Hashable identity.
private struct TestSnapshot: ShareableRecord {
    let id: UUID
    var updatedAt: Date
    var payload: String = ""

    static let ckRecordType = "TestSnapshot"

    func encode(into record: CKRecord) {
        record["id"] = id.uuidString as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        record["payload"] = payload as CKRecordValue
    }

    init(id: UUID, updatedAt: Date, payload: String = "") {
        self.id = id
        self.updatedAt = updatedAt
        self.payload = payload
    }

    init?(record: CKRecord) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let updatedAt = record["updatedAt"] as? Date else { return nil }
        self.id = id
        self.updatedAt = updatedAt
        self.payload = (record["payload"] as? String) ?? ""
    }
}

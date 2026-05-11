import CloudKit
import Foundation
import Testing
@testable import Chorez

// EventSnapshot CKRecord round-trip suite. Split from
// `CKRecordSerializerTests.swift` so the other suites stay under the
// 400-line lint cap; EventSnapshot needs a case per `EventPayload`
// variant plus a few negatives, which is a lot of `@Test`.

private typealias Fixture = CKSerializerFixture

@Suite("EventSnapshot CKRecord round-trip")
struct EventSnapshotSerializerTests {
    @Test("Round-trip preserves payload (choreCompleted)")
    func payloadChoreCompleted() throws {
        let payload: EventPayload = .choreCompleted(instanceID: Fixture.instanceID, points: 5)
        let original = Fixture.event(payload: payload)
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(EventSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Round-trip preserves payload (awardGiven), positive, negative, zero")
    func payloadAwardGiven() throws {
        for points in [7, -3, 0] {
            let original = Fixture.event(payload: .awardGiven(points: points))
            let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
            original.encode(into: record)
            let decoded = try #require(EventSnapshot(record: record))
            #expect(decoded == original)
        }
    }

    @Test("Round-trip preserves payload (rewardRedeemed)")
    func payloadRewardRedeemed() throws {
        let payload: EventPayload = .rewardRedeemed(rewardID: Fixture.rewardID,
                                                    redemptionID: Fixture.redemptionID,
                                                    points: 4)
        let original = Fixture.event(payload: payload)
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(EventSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Round-trip preserves payload (dayClosed) with nil kidID")
    func payloadDayClosed() throws {
        let original = Fixture.event(payload: .dayClosed(previousBalance: 12), kidID: nil)
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        original.encode(into: record)
        // dayClosed events have nil kidID — verify the optional UUID
        // encode path actually omits the field.
        #expect(record["kidID"] == nil)

        let decoded = try #require(EventSnapshot(record: record))
        #expect(decoded.kidID == nil)
        #expect(decoded == original)
    }

    @Test("Type discriminator written alongside payload blob")
    func typeDiscriminatorPresent() {
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        Fixture.event(payload: .awardGiven(points: 1)).encode(into: record)
        #expect(record["type"] as? String == EventType.awardGiven.rawValue)
    }

    @Test("Missing payload blob returns nil")
    func missingPayloadFails() {
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        Fixture.event(payload: .awardGiven(points: 1)).encode(into: record)
        record["payload"] = nil
        #expect(EventSnapshot(record: record) == nil)
    }

    @Test("Malformed payload bytes return nil")
    func malformedPayloadFails() {
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        Fixture.event(payload: .awardGiven(points: 1)).encode(into: record)
        record["payload"] = Data("not json".utf8) as CKRecordValue
        #expect(EventSnapshot(record: record) == nil)
    }

    @Test("Missing updatedAt returns nil")
    func missingUpdatedAtFails() {
        let record = Fixture.freshRecord(type: EventSnapshot.ckRecordType)
        Fixture.event(payload: .awardGiven(points: 1)).encode(into: record)
        record["updatedAt"] = nil
        #expect(EventSnapshot(record: record) == nil)
    }

    @Test("ckRecordType is 'Event'")
    func recordTypeName() {
        #expect(EventSnapshot.ckRecordType == "Event")
    }
}

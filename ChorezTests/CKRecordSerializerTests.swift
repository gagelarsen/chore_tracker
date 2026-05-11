import CloudKit
import Foundation
import Testing
@testable import Chorez

// CKRecord serializer round-trip + negative tests for every non-Event
// snapshot. EventSnapshot's four payload cases are tested separately in
// `CKRecordSerializerEventTests.swift` so neither file overflows the
// 400-line lint cap.
//
// We construct fresh CKRecords directly rather than going through
// CloudKit so tests don't need any container, zone, or network.

private typealias Fixture = CKSerializerFixture

// MARK: - HouseholdSnapshot

@Suite("HouseholdSnapshot CKRecord round-trip")
struct HouseholdSnapshotSerializerTests {
    @Test("Round-trip with every optional populated")
    func roundTripFullyPopulated() throws {
        let original = Fixture.household()
        let record = Fixture.freshRecord(type: HouseholdSnapshot.ckRecordType)
        original.encode(into: record)

        let decoded = try #require(HouseholdSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Round-trip with optional UUID/Date fields nil omits them on encode")
    func roundTripOptionalsNil() throws {
        let original = Fixture.householdMinimal()
        let record = Fixture.freshRecord(type: HouseholdSnapshot.ckRecordType)
        original.encode(into: record)

        // Verify encode actually omitted nil fields (no NSNull); this is
        // the load-bearing decision: present-but-null vs. absent would
        // otherwise be ambiguous on the read side.
        #expect(record["ownerCloudUserID"] == nil)
        #expect(record["lastAutoFillDate"] == nil)

        let decoded = try #require(HouseholdSnapshot(record: record))
        #expect(decoded.ownerCloudUserID == nil)
        #expect(decoded.lastAutoFillDate == nil)
        #expect(decoded == original)
    }

    @Test("Missing required field returns nil")
    func missingRequiredFieldFails() {
        let original = Fixture.household()
        let record = Fixture.freshRecord(type: HouseholdSnapshot.ckRecordType)
        original.encode(into: record)
        record["name"] = nil  // drop a required field
        #expect(HouseholdSnapshot(record: record) == nil)
    }

    @Test("ckRecordType matches the Snapshot suffix-stripped name")
    func recordTypeName() {
        #expect(HouseholdSnapshot.ckRecordType == "Household")
    }
}

// MARK: - KidSnapshot

@Suite("KidSnapshot CKRecord round-trip")
struct KidSnapshotSerializerTests {
    @Test("Round-trip preserves all fields")
    func roundTrip() throws {
        let original = Fixture.kid()
        let record = Fixture.freshRecord(type: KidSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(KidSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Missing currentDailyBalance returns nil")
    func missingFieldFails() {
        let record = Fixture.freshRecord(type: KidSnapshot.ckRecordType)
        Fixture.kid().encode(into: record)
        record["currentDailyBalance"] = nil
        #expect(KidSnapshot(record: record) == nil)
    }

    @Test("Malformed UUID string returns nil")
    func malformedUUIDFails() {
        let record = Fixture.freshRecord(type: KidSnapshot.ckRecordType)
        Fixture.kid().encode(into: record)
        record["id"] = "not-a-uuid" as CKRecordValue
        #expect(KidSnapshot(record: record) == nil)
    }

    @Test("ckRecordType is 'Kid'")
    func recordTypeName() {
        #expect(KidSnapshot.ckRecordType == "Kid")
    }
}

// MARK: - ChoreTemplateSnapshot

@Suite("ChoreTemplateSnapshot CKRecord round-trip")
struct ChoreTemplateSnapshotSerializerTests {
    @Test("Round-trip preserves daysOfWeekBitmask and all fields")
    func roundTrip() throws {
        let original = Fixture.template()
        let record = Fixture.freshRecord(type: ChoreTemplateSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(ChoreTemplateSnapshot(record: record))
        #expect(decoded == original)
        // Spot-check: bitmask encoded as native Int in the record.
        #expect(record["daysOfWeekBitmask"] as? Int == Recurrence.daily.daysOfWeekBitmask)
    }

    @Test("Round-trip preserves a non-daily weekday pattern")
    func roundTripWeekends() throws {
        var snapshot = Fixture.template()
        snapshot.recurrence = .weekends
        let record = Fixture.freshRecord(type: ChoreTemplateSnapshot.ckRecordType)
        snapshot.encode(into: record)
        let decoded = try #require(ChoreTemplateSnapshot(record: record))
        #expect(decoded.recurrence == .weekends)
        #expect(decoded == snapshot)
    }

    @Test("Missing daysOfWeekBitmask field falls back to .daily")
    func missingBitmaskFallsBackToDaily() throws {
        let record = Fixture.freshRecord(type: ChoreTemplateSnapshot.ckRecordType)
        Fixture.template().encode(into: record)
        record["daysOfWeekBitmask"] = nil
        let decoded = try #require(ChoreTemplateSnapshot(record: record))
        #expect(decoded.recurrence == .daily)
    }

    @Test("Missing assignedKidID returns nil")
    func missingFieldFails() {
        let record = Fixture.freshRecord(type: ChoreTemplateSnapshot.ckRecordType)
        Fixture.template().encode(into: record)
        record["assignedKidID"] = nil
        #expect(ChoreTemplateSnapshot(record: record) == nil)
    }

    @Test("ckRecordType is 'ChoreTemplate'")
    func recordTypeName() {
        #expect(ChoreTemplateSnapshot.ckRecordType == "ChoreTemplate")
    }
}

// MARK: - ChoreInstanceSnapshot

@Suite("ChoreInstanceSnapshot CKRecord round-trip")
struct ChoreInstanceSnapshotSerializerTests {
    @Test("Round-trip with completedAt populated")
    func roundTripCompleted() throws {
        let original = Fixture.instance(completedAt: Fixture.altClock, status: .done)
        let record = Fixture.freshRecord(type: ChoreInstanceSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(ChoreInstanceSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Round-trip with templateID nil omits the field and decodes as nil")
    func optionalTemplateIDNilRoundTrips() throws {
        let original = Fixture.instance(templateID: nil)
        let record = Fixture.freshRecord(type: ChoreInstanceSnapshot.ckRecordType)
        original.encode(into: record)
        #expect(record["templateID"] == nil)

        let decoded = try #require(ChoreInstanceSnapshot(record: record))
        #expect(decoded.templateID == nil)
        #expect(decoded == original)
    }

    @Test("Round-trip with completedAt nil omits the field")
    func optionalCompletedAtNilRoundTrips() throws {
        let original = Fixture.instance(completedAt: nil)
        let record = Fixture.freshRecord(type: ChoreInstanceSnapshot.ckRecordType)
        original.encode(into: record)
        #expect(record["completedAt"] == nil)

        let decoded = try #require(ChoreInstanceSnapshot(record: record))
        #expect(decoded.completedAt == nil)
    }

    @Test("Missing status returns nil")
    func missingStatusFails() {
        let record = Fixture.freshRecord(type: ChoreInstanceSnapshot.ckRecordType)
        Fixture.instance().encode(into: record)
        record["status"] = nil
        #expect(ChoreInstanceSnapshot(record: record) == nil)
    }

    @Test("Malformed templateID (present but unparseable) returns nil")
    func malformedOptionalUUIDFails() {
        let record = Fixture.freshRecord(type: ChoreInstanceSnapshot.ckRecordType)
        Fixture.instance().encode(into: record)
        record["templateID"] = "garbage" as CKRecordValue
        #expect(ChoreInstanceSnapshot(record: record) == nil)
    }

    @Test("ckRecordType is 'ChoreInstance'")
    func recordTypeName() {
        #expect(ChoreInstanceSnapshot.ckRecordType == "ChoreInstance")
    }
}

// MARK: - RewardSnapshot

@Suite("RewardSnapshot CKRecord round-trip")
struct RewardSnapshotSerializerTests {
    @Test("Round-trip preserves all fields")
    func roundTrip() throws {
        let original = Fixture.reward()
        let record = Fixture.freshRecord(type: RewardSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(RewardSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Missing active returns nil")
    func missingActiveFails() {
        let record = Fixture.freshRecord(type: RewardSnapshot.ckRecordType)
        Fixture.reward().encode(into: record)
        record["active"] = nil
        #expect(RewardSnapshot(record: record) == nil)
    }

    @Test("ckRecordType is 'Reward'")
    func recordTypeName() {
        #expect(RewardSnapshot.ckRecordType == "Reward")
    }
}

// MARK: - RewardRedemptionSnapshot

@Suite("RewardRedemptionSnapshot CKRecord round-trip")
struct RewardRedemptionSnapshotSerializerTests {
    @Test("Round-trip preserves all fields")
    func roundTrip() throws {
        let original = Fixture.redemption()
        let record = Fixture.freshRecord(type: RewardRedemptionSnapshot.ckRecordType)
        original.encode(into: record)
        let decoded = try #require(RewardRedemptionSnapshot(record: record))
        #expect(decoded == original)
    }

    @Test("Missing redeemedAt returns nil")
    func missingFieldFails() {
        let record = Fixture.freshRecord(type: RewardRedemptionSnapshot.ckRecordType)
        Fixture.redemption().encode(into: record)
        record["redeemedAt"] = nil
        #expect(RewardRedemptionSnapshot(record: record) == nil)
    }

    @Test("ckRecordType is 'RewardRedemption'")
    func recordTypeName() {
        #expect(RewardRedemptionSnapshot.ckRecordType == "RewardRedemption")
    }
}

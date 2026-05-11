import CloudKit
import Foundation
@testable import Chorez

// Shared fixture for the CKRecord serializer test suites.
//
// Lives in its own file because the suites split across two test
// files (one for non-Event snapshots, one for EventSnapshot's four
// payload cases) and both need the same canonical UUIDs + fixed
// clock to keep round-trip assertions byte-stable.

enum CKSerializerFixture {
    /// Fixed clock so the encoded `updatedAt` is byte-equal across
    /// runs — encoding is otherwise non-deterministic on `.now`.
    static let clock = Date(timeIntervalSince1970: 1_700_000_000)
    /// Distinct second clock for fields like `completedAt` that should
    /// not happen to equal `clock` (catches a bug where encode/decode
    /// silently swaps two same-typed fields).
    static let altClock = Date(timeIntervalSince1970: 1_700_086_400)

    static let householdID = UUID()
    static let kidID = UUID()
    static let templateID = UUID()
    static let instanceID = UUID()
    static let rewardID = UUID()
    static let redemptionID = UUID()
    static let eventID = UUID()

    /// Mint a fresh CKRecord without going through a real zone. The
    /// recordName is a UUID string so the format matches what the
    /// live share zone will use.
    static func freshRecord(type: String, name: String = UUID().uuidString) -> CKRecord {
        CKRecord(recordType: type,
                 recordID: CKRecord.ID(recordName: name))
    }

    static func household() -> HouseholdSnapshot {
        HouseholdSnapshot(id: householdID,
                          name: "Family",
                          ownerCloudUserID: "user-1",
                          createdAt: clock,
                          lastAutoFillDate: clock,
                          updatedAt: clock)
    }

    static func householdMinimal() -> HouseholdSnapshot {
        // Both optional fields nil — exercises the "omit on encode,
        // read as nil on decode" path.
        HouseholdSnapshot(id: householdID,
                          name: "Family",
                          ownerCloudUserID: nil,
                          createdAt: clock,
                          lastAutoFillDate: nil,
                          updatedAt: clock)
    }

    static func kid() -> KidSnapshot {
        KidSnapshot(id: kidID,
                    householdID: householdID,
                    name: "Anna",
                    displayOrder: 1,
                    currentDailyBalance: 7,
                    updatedAt: clock)
    }

    static func template() -> ChoreTemplateSnapshot {
        ChoreTemplateSnapshot(id: templateID,
                              householdID: householdID,
                              name: "Dishes",
                              points: 5,
                              assignedKidID: kidID,
                              recurrence: .daily,
                              active: true,
                              updatedAt: clock)
    }

    static func instance(templateID: UUID? = CKSerializerFixture.templateID,
                         completedAt: Date? = nil,
                         status: ChoreStatus = .pending) -> ChoreInstanceSnapshot {
        ChoreInstanceSnapshot(id: instanceID,
                              templateID: templateID,
                              householdID: householdID,
                              name: "Dishes",
                              points: 5,
                              assignedKidID: kidID,
                              date: clock,
                              status: status,
                              completedAt: completedAt,
                              updatedAt: clock)
    }

    static func reward() -> RewardSnapshot {
        RewardSnapshot(id: rewardID,
                       householdID: householdID,
                       name: "Sticker",
                       points: 4,
                       active: true,
                       updatedAt: clock)
    }

    static func redemption() -> RewardRedemptionSnapshot {
        RewardRedemptionSnapshot(id: redemptionID,
                                 kidID: kidID,
                                 rewardID: rewardID,
                                 points: 4,
                                 redeemedAt: clock,
                                 updatedAt: clock)
    }

    static func event(payload: EventPayload,
                      kidID: UUID? = CKSerializerFixture.kidID) -> EventSnapshot {
        EventSnapshot(id: eventID,
                      kidID: kidID,
                      payload: payload,
                      occurredAt: clock,
                      updatedAt: clock)
    }
}

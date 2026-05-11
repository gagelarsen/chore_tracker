import CloudKit
import Foundation

// `CKRecord` <-> `*Snapshot` round-trip conformances.
//
// Every snapshot in `Chorez/Domain/HouseholdState.swift` implements
// `ShareableRecord` here. The conformances are factored as `extension`s
// on the snapshot types (rather than living next to each `struct`) so
// the domain layer stays free of any CloudKit import; only the sync
// layer pays the framework cost.
//
// Encoding conventions (see `SyncProtocols.swift` doc comment for the
// full contract):
//
// - `UUID` round-trips as `uuidString`. CloudKit doesn't have a UUID
//   primitive and our schema picks string-with-known-format over
//   16-byte blobs so the records stay legible in the dashboard.
// - Optional `UUID?` / `Date?`: we omit the field from the record
//   entirely when nil (do NOT write `NSNull`). On decode, a missing
//   field reads as `nil`. This keeps the schema sparse and avoids the
//   tri-state "present-but-null vs. absent" ambiguity.
// - String-raw enums (`ChoreStatus`, `Recurrence`) write/read their
//   raw value. Decode failures (unknown raw) return `nil` from
//   `init?(record:)`.
// - `EventPayload` JSON-encodes to `Data` (the same encoder/decoder
//   the SwiftData `Event` model uses, so the byte layout is identical
//   across the persistence and sync boundaries).
//
// `init?(record:)` returns `nil` on any decode failure (missing
// required field, wrong type, malformed enum/UUID/JSON). Per the
// protocol contract the sync layer treats `nil` as "skip this record
// for now" rather than crashing.

// MARK: - Shared helpers

/// Stable JSON encoder used for `EventPayload` round-trips.
///
/// `.sortedKeys` keeps the encoded bytes deterministic, which matters
/// because CloudKit Data-field equality is byte-equal: a re-encode that
/// reordered keys would look like a change to the sync engine and
/// trigger a redundant write.
private let payloadEncoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return enc
}()
private let payloadDecoder = JSONDecoder()

/// Shorthand for "decode this CKRecord field as a `UUID`, or return
/// `nil` from the caller if it's missing/malformed". Used as the right
/// half of `guard let uuid = decodeUUID(...)` in every `init?(record:)`.
private func decodeUUID(_ record: CKRecord, _ key: String) -> UUID? {
    guard let raw = record[key] as? String else { return nil }
    return UUID(uuidString: raw)
}

/// Optional-UUID variant: returns `.some(nil)` when the field is
/// absent, `.some(uuid)` when present and valid, and `nil` only when
/// the field is present but malformed.
///
/// The double-Optional shape lets callers distinguish "decode failed,
/// fail the whole record" from "field legitimately nil, continue".
private func decodeOptionalUUID(_ record: CKRecord, _ key: String) -> UUID?? {
    guard let raw = record[key] else { return .some(nil) }
    guard let str = raw as? String, let uuid = UUID(uuidString: str) else {
        return nil
    }
    return .some(uuid)
}

/// Encode a `UUID` as its string form (CloudKit has no UUID type).
private func encodeUUID(_ value: UUID) -> CKRecordValue {
    value.uuidString as CKRecordValue
}

// MARK: - HouseholdSnapshot

extension HouseholdSnapshot: ShareableRecord {
    public static var ckRecordType: String { "Household" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        record["name"] = name as CKRecordValue
        // Omit optional fields entirely when nil so the dashboard schema
        // stays sparse and decode reads them as `nil` without ambiguity.
        if let ownerCloudUserID {
            record["ownerCloudUserID"] = ownerCloudUserID as CKRecordValue
        }
        record["createdAt"] = createdAt as CKRecordValue
        if let lastAutoFillDate {
            record["lastAutoFillDate"] = lastAutoFillDate as CKRecordValue
        }
        record["updatedAt"] = updatedAt as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let name = record["name"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        self.init(id: id,
                  name: name,
                  ownerCloudUserID: record["ownerCloudUserID"] as? String,
                  createdAt: createdAt,
                  lastAutoFillDate: record["lastAutoFillDate"] as? Date,
                  updatedAt: updatedAt)
    }
}

// MARK: - KidSnapshot

extension KidSnapshot: ShareableRecord {
    public static var ckRecordType: String { "Kid" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        record["householdID"] = encodeUUID(householdID)
        record["name"] = name as CKRecordValue
        record["displayOrder"] = displayOrder as CKRecordValue
        record["currentDailyBalance"] = currentDailyBalance as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let householdID = decodeUUID(record, "householdID"),
              let name = record["name"] as? String,
              let displayOrder = record["displayOrder"] as? Int,
              let currentDailyBalance = record["currentDailyBalance"] as? Int,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        self.init(id: id,
                  householdID: householdID,
                  name: name,
                  displayOrder: displayOrder,
                  currentDailyBalance: currentDailyBalance,
                  updatedAt: updatedAt)
    }
}

// MARK: - ChoreTemplateSnapshot

extension ChoreTemplateSnapshot: ShareableRecord {
    public static var ckRecordType: String { "ChoreTemplate" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        record["householdID"] = encodeUUID(householdID)
        record["name"] = name as CKRecordValue
        record["points"] = points as CKRecordValue
        record["assignedKidID"] = encodeUUID(assignedKidID)
        // 7-bit weekday mask; same shape as SwiftData column.
        record["daysOfWeekBitmask"] = recurrence.daysOfWeekBitmask as CKRecordValue
        record["active"] = active as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let householdID = decodeUUID(record, "householdID"),
              let name = record["name"] as? String,
              let points = record["points"] as? Int,
              let assignedKidID = decodeUUID(record, "assignedKidID"),
              let active = record["active"] as? Bool,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        // Pre-Phase-1.6 records used a String `recurrence` field;
        // missing-key tolerance falls back to `.daily` so records
        // written by the old schema still inflate correctly during a
        // rolling upgrade.
        let bitmask = (record["daysOfWeekBitmask"] as? Int) ?? Recurrence.daily.daysOfWeekBitmask
        let recurrence = Recurrence(daysOfWeekBitmask: bitmask)
        self.init(id: id,
                  householdID: householdID,
                  name: name,
                  points: points,
                  assignedKidID: assignedKidID,
                  recurrence: recurrence,
                  active: active,
                  updatedAt: updatedAt)
    }
}

// MARK: - ChoreInstanceSnapshot

extension ChoreInstanceSnapshot: ShareableRecord {
    public static var ckRecordType: String { "ChoreInstance" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        if let templateID {
            record["templateID"] = encodeUUID(templateID)
        }
        record["householdID"] = encodeUUID(householdID)
        record["name"] = name as CKRecordValue
        record["points"] = points as CKRecordValue
        record["assignedKidID"] = encodeUUID(assignedKidID)
        record["date"] = date as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        if let completedAt {
            record["completedAt"] = completedAt as CKRecordValue
        }
        record["updatedAt"] = updatedAt as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let householdID = decodeUUID(record, "householdID"),
              let name = record["name"] as? String,
              let points = record["points"] as? Int,
              let assignedKidID = decodeUUID(record, "assignedKidID"),
              let date = record["date"] as? Date,
              let statusRaw = record["status"] as? String,
              let status = ChoreStatus(rawValue: statusRaw),
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        // Optional UUID gets the tri-state decode: distinguish absent
        // (legit nil) from present-but-malformed (whole record fails).
        guard let templateID = decodeOptionalUUID(record, "templateID") else {
            return nil
        }
        self.init(id: id,
                  templateID: templateID,
                  householdID: householdID,
                  name: name,
                  points: points,
                  assignedKidID: assignedKidID,
                  date: date,
                  status: status,
                  completedAt: record["completedAt"] as? Date,
                  updatedAt: updatedAt)
    }
}

// MARK: - RewardSnapshot

extension RewardSnapshot: ShareableRecord {
    public static var ckRecordType: String { "Reward" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        record["householdID"] = encodeUUID(householdID)
        record["name"] = name as CKRecordValue
        record["points"] = points as CKRecordValue
        record["active"] = active as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let householdID = decodeUUID(record, "householdID"),
              let name = record["name"] as? String,
              let points = record["points"] as? Int,
              let active = record["active"] as? Bool,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        self.init(id: id,
                  householdID: householdID,
                  name: name,
                  points: points,
                  active: active,
                  updatedAt: updatedAt)
    }
}

// MARK: - RewardRedemptionSnapshot

extension RewardRedemptionSnapshot: ShareableRecord {
    public static var ckRecordType: String { "RewardRedemption" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        record["kidID"] = encodeUUID(kidID)
        record["rewardID"] = encodeUUID(rewardID)
        record["points"] = points as CKRecordValue
        record["redeemedAt"] = redeemedAt as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let kidID = decodeUUID(record, "kidID"),
              let rewardID = decodeUUID(record, "rewardID"),
              let points = record["points"] as? Int,
              let redeemedAt = record["redeemedAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        self.init(id: id,
                  kidID: kidID,
                  rewardID: rewardID,
                  points: points,
                  redeemedAt: redeemedAt,
                  updatedAt: updatedAt)
    }
}

// MARK: - EventSnapshot

extension EventSnapshot: ShareableRecord {
    public static var ckRecordType: String { "Event" }

    public func encode(into record: CKRecord) {
        record["id"] = encodeUUID(id)
        // Optional `kidID`: `dayClosed` events carry nil. Encoded the
        // same tri-state way as other optional UUIDs.
        if let kidID {
            record["kidID"] = encodeUUID(kidID)
        }
        record["occurredAt"] = occurredAt as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        // Payload is JSON-encoded to Data; the same encoder the
        // SwiftData `Event` model uses, so bytes match across layers.
        // Force-try is acceptable: `EventPayload` is a finite Codable
        // enum we control, so encoding cannot fail at runtime.
        // swiftlint:disable:next force_try
        let payloadData = try! payloadEncoder.encode(payload)
        record["payload"] = payloadData as CKRecordValue
        // Duplicate discriminator so the CloudKit dashboard / queries
        // can filter by event type without fetching the payload blob.
        record["type"] = payload.type.rawValue as CKRecordValue
    }

    public init?(record: CKRecord) {
        guard let id = decodeUUID(record, "id"),
              let occurredAt = record["occurredAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date,
              let payloadData = record["payload"] as? Data,
              let payload = try? payloadDecoder.decode(EventPayload.self,
                                                       from: payloadData) else {
            return nil
        }
        // Optional UUID with tri-state decode.
        guard let kidID = decodeOptionalUUID(record, "kidID") else {
            return nil
        }
        self.init(id: id,
                  kidID: kidID,
                  payload: payload,
                  occurredAt: occurredAt,
                  updatedAt: updatedAt)
    }
}

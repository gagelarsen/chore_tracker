import Foundation
import SwiftData

/// Persistent `Household` row.
///
/// In Phase 1 only one household exists per app install (the owner-parent
/// creates it on first launch). CloudKit + `CKShare` in PR3 will let a
/// second parent join the same household record. Properties default to
/// safe values so the schema is CloudKit-ready when that lands.
@Model
public final class Household {
    // Property-level defaults satisfy SwiftData's CloudKit requirement
    // that every non-optional column be defaulted or optional — without
    // them the container init can fail at runtime even though the
    // schema compiles. Init signatures further down keep their own
    // defaults for ergonomic Swift call sites.
    public var id: UUID = UUID()
    public var name: String = ""
    public var ownerCloudUserID: String?
    public var createdAt: Date = Date()
    /// `startOfDay` of the most recent run of `autoFillTodayIfNeeded`.
    /// Keeps auto-fill idempotent across same-day app launches.
    public var lastAutoFillDate: Date?
    /// LWW (last-writer-wins) arbiter for CloudKit sync. Every mutation
    /// path that changes a persisted field also stamps this with `.now`
    /// so the shared-zone sync engine can resolve concurrent edits by
    /// keeping the higher timestamp. See `Chorez/Sync/SyncProtocols.swift`.
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(),
                name: String = "",
                ownerCloudUserID: String? = nil,
                createdAt: Date = .now,
                lastAutoFillDate: Date? = nil,
                updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.ownerCloudUserID = ownerCloudUserID
        self.createdAt = createdAt
        self.lastAutoFillDate = lastAutoFillDate
        self.updatedAt = updatedAt
    }

    public convenience init(snapshot: HouseholdSnapshot) {
        self.init(id: snapshot.id,
                  name: snapshot.name,
                  ownerCloudUserID: snapshot.ownerCloudUserID,
                  createdAt: snapshot.createdAt,
                  lastAutoFillDate: snapshot.lastAutoFillDate,
                  updatedAt: snapshot.updatedAt)
    }

    public var snapshot: HouseholdSnapshot {
        HouseholdSnapshot(id: id,
                          name: name,
                          ownerCloudUserID: ownerCloudUserID,
                          createdAt: createdAt,
                          lastAutoFillDate: lastAutoFillDate,
                          updatedAt: updatedAt)
    }
}

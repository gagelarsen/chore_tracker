import Foundation
import SwiftData

/// Persistent per-day chore row.
///
/// One `ChoreInstance` per kid per chore per day. `templateID` is `nil`
/// for ad-hoc chores added directly to a day (no parent template).
/// `date` is the `startOfDay` for which this instance was scheduled, so
/// queries like "today's instances" stay simple and timezone-stable.
@Model
public final class ChoreInstance {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var templateID: UUID?
    public var householdID: UUID = UUID()
    public var name: String = ""
    public var points: Int = 0
    public var assignedKidID: UUID = UUID()
    public var date: Date = Date()
    public var statusRaw: String = ChoreStatus.pending.rawValue
    public var completedAt: Date?
    /// LWW arbiter for CloudKit sync — see `Household.updatedAt`.
    public var updatedAt: Date = Date()

    public var status: ChoreStatus {
        get { ChoreStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(),
                templateID: UUID? = nil,
                householdID: UUID,
                name: String = "",
                points: Int = 0,
                assignedKidID: UUID,
                date: Date,
                status: ChoreStatus = .pending,
                completedAt: Date? = nil,
                updatedAt: Date = .now) {
        self.id = id
        self.templateID = templateID
        self.householdID = householdID
        self.name = name
        self.points = points
        self.assignedKidID = assignedKidID
        self.date = date
        self.statusRaw = status.rawValue
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }

    public convenience init(snapshot: ChoreInstanceSnapshot) {
        self.init(id: snapshot.id,
                  templateID: snapshot.templateID,
                  householdID: snapshot.householdID,
                  name: snapshot.name,
                  points: snapshot.points,
                  assignedKidID: snapshot.assignedKidID,
                  date: snapshot.date,
                  status: snapshot.status,
                  completedAt: snapshot.completedAt,
                  updatedAt: snapshot.updatedAt)
    }

    public var snapshot: ChoreInstanceSnapshot {
        ChoreInstanceSnapshot(id: id,
                              templateID: templateID,
                              householdID: householdID,
                              name: name,
                              points: points,
                              assignedKidID: assignedKidID,
                              date: date,
                              status: status,
                              completedAt: completedAt,
                              updatedAt: updatedAt)
    }
}

import Foundation
import SwiftData

/// Persistent recurring-chore definition. `ChoreInstance` rows are
/// generated from active templates by `ChoreRepository.autoFillTodayIfNeeded`,
/// gated by `recurrence.includes(weekday:)`.
///
/// `daysOfWeekBitmask` is stored as a plain `Int` rather than the
/// `Recurrence` struct directly: SwiftData has sharp edges with
/// associated-value Codable types and CloudKit's native `Int` field
/// type round-trips cleanly. The struct is a transient façade
/// computed from the bitmask.
@Model
public final class ChoreTemplate {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var householdID: UUID = UUID()
    public var name: String = ""
    public var points: Int = 0
    public var assignedKidID: UUID = UUID()
    /// 7-bit mask, bit `Weekday.bitOffset` set = active on that day.
    /// `127` (all 7 bits) matches the v1 daily-only behaviour; this
    /// default also covers existing data that pre-dates Phase 1.6 —
    /// SwiftData hydrates a missing column as `127`, so rows from
    /// before the schema change still spawn every day.
    public var daysOfWeekBitmask: Int = 127
    public var active: Bool = true
    /// LWW arbiter for CloudKit sync — see `Household.updatedAt`.
    public var updatedAt: Date = Date()

    public var recurrence: Recurrence {
        get { Recurrence(daysOfWeekBitmask: daysOfWeekBitmask) }
        set { daysOfWeekBitmask = newValue.daysOfWeekBitmask }
    }

    public init(id: UUID = UUID(),
                householdID: UUID,
                name: String = "",
                points: Int = 0,
                assignedKidID: UUID,
                recurrence: Recurrence = .daily,
                active: Bool = true,
                updatedAt: Date = .now) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.points = points
        self.assignedKidID = assignedKidID
        self.daysOfWeekBitmask = recurrence.daysOfWeekBitmask
        self.active = active
        self.updatedAt = updatedAt
    }

    public convenience init(snapshot: ChoreTemplateSnapshot) {
        self.init(id: snapshot.id,
                  householdID: snapshot.householdID,
                  name: snapshot.name,
                  points: snapshot.points,
                  assignedKidID: snapshot.assignedKidID,
                  recurrence: snapshot.recurrence,
                  active: snapshot.active,
                  updatedAt: snapshot.updatedAt)
    }

    public var snapshot: ChoreTemplateSnapshot {
        ChoreTemplateSnapshot(id: id,
                              householdID: householdID,
                              name: name,
                              points: points,
                              assignedKidID: assignedKidID,
                              recurrence: recurrence,
                              active: active,
                              updatedAt: updatedAt)
    }
}

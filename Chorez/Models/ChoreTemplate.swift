import Foundation
import SwiftData

/// Persistent recurring-chore definition. `ChoreInstance` rows are
/// generated from active templates by `ChoreRepository.autoFillTodayIfNeeded`.
///
/// `recurrence` is stored as its raw value (a plain `String`) rather than
/// the `Recurrence` enum directly: SwiftData has well-known sharp edges
/// with associated-value enums and CloudKit can't reliably round-trip
/// custom Codable types either, so we keep stored properties to
/// CloudKit-friendly primitives.
@Model
public final class ChoreTemplate {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var householdID: UUID = UUID()
    public var name: String = ""
    public var points: Int = 0
    public var assignedKidID: UUID = UUID()
    public var recurrenceRaw: String = Recurrence.daily.rawValue
    public var active: Bool = true

    public var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .daily }
        set { recurrenceRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(),
                householdID: UUID,
                name: String = "",
                points: Int = 0,
                assignedKidID: UUID,
                recurrence: Recurrence = .daily,
                active: Bool = true) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.points = points
        self.assignedKidID = assignedKidID
        self.recurrenceRaw = recurrence.rawValue
        self.active = active
    }

    public convenience init(snapshot: ChoreTemplateSnapshot) {
        self.init(id: snapshot.id,
                  householdID: snapshot.householdID,
                  name: snapshot.name,
                  points: snapshot.points,
                  assignedKidID: snapshot.assignedKidID,
                  recurrence: snapshot.recurrence,
                  active: snapshot.active)
    }

    public var snapshot: ChoreTemplateSnapshot {
        ChoreTemplateSnapshot(id: id,
                              householdID: householdID,
                              name: name,
                              points: points,
                              assignedKidID: assignedKidID,
                              recurrence: recurrence,
                              active: active)
    }
}

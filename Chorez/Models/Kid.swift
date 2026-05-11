import Foundation
import SwiftData

/// Persistent `Kid` row.
///
/// `currentDailyBalance` is the canonical points-earned-today counter.
/// Per `00-standards.md`, the only path that mutates this field is
/// `RulesEngine.applyAward` (via `HouseholdRepository.applyEngine`).
/// `displayOrder` is creation-time index in Phase 1; drag-to-reorder UI
/// is deferred to Phase 5 polish.
@Model
public final class Kid {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var householdID: UUID = UUID()
    public var name: String = ""
    public var displayOrder: Int = 0
    public var currentDailyBalance: Int = 0
    /// LWW arbiter for CloudKit sync — see `Household.updatedAt`.
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(),
                householdID: UUID,
                name: String = "",
                displayOrder: Int = 0,
                currentDailyBalance: Int = 0,
                updatedAt: Date = .now) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.displayOrder = displayOrder
        self.currentDailyBalance = currentDailyBalance
        self.updatedAt = updatedAt
    }

    public convenience init(snapshot: KidSnapshot) {
        self.init(id: snapshot.id,
                  householdID: snapshot.householdID,
                  name: snapshot.name,
                  displayOrder: snapshot.displayOrder,
                  currentDailyBalance: snapshot.currentDailyBalance,
                  updatedAt: snapshot.updatedAt)
    }

    public var snapshot: KidSnapshot {
        KidSnapshot(id: id,
                    householdID: householdID,
                    name: name,
                    displayOrder: displayOrder,
                    currentDailyBalance: currentDailyBalance,
                    updatedAt: updatedAt)
    }
}

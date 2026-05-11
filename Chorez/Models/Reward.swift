import Foundation
import SwiftData

/// Persistent redeemable reward defined by parents.
@Model
public final class Reward {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var householdID: UUID = UUID()
    public var name: String = ""
    public var points: Int = 0
    public var active: Bool = true
    /// LWW arbiter for CloudKit sync — see `Household.updatedAt`.
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(),
                householdID: UUID,
                name: String = "",
                points: Int = 0,
                active: Bool = true,
                updatedAt: Date = .now) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.points = points
        self.active = active
        self.updatedAt = updatedAt
    }

    public convenience init(snapshot: RewardSnapshot) {
        self.init(id: snapshot.id,
                  householdID: snapshot.householdID,
                  name: snapshot.name,
                  points: snapshot.points,
                  active: snapshot.active,
                  updatedAt: snapshot.updatedAt)
    }

    public var snapshot: RewardSnapshot {
        RewardSnapshot(id: id,
                       householdID: householdID,
                       name: name,
                       points: points,
                       active: active,
                       updatedAt: updatedAt)
    }
}

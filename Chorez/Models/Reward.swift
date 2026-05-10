import Foundation
import SwiftData

/// Persistent redeemable reward defined by parents.
@Model
public final class Reward {
    public var id: UUID
    public var householdID: UUID
    public var name: String
    public var points: Int
    public var active: Bool

    public init(id: UUID = UUID(),
                householdID: UUID,
                name: String = "",
                points: Int = 0,
                active: Bool = true) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.points = points
        self.active = active
    }

    public convenience init(snapshot: RewardSnapshot) {
        self.init(id: snapshot.id,
                  householdID: snapshot.householdID,
                  name: snapshot.name,
                  points: snapshot.points,
                  active: snapshot.active)
    }

    public var snapshot: RewardSnapshot {
        RewardSnapshot(id: id,
                       householdID: householdID,
                       name: name,
                       points: points,
                       active: active)
    }
}

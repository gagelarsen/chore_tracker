import Foundation
import SwiftData

/// Append-only record of a redemption.
///
/// `points` captures the reward's cost at the moment of redemption so
/// historical reads stay correct even if the underlying `Reward` is
/// re-priced or deactivated afterward.
@Model
public final class RewardRedemption {
    // Property-level defaults — see Household.swift for the rationale.
    public var id: UUID = UUID()
    public var kidID: UUID = UUID()
    public var rewardID: UUID = UUID()
    public var points: Int = 0
    public var redeemedAt: Date = Date()

    public init(id: UUID = UUID(),
                kidID: UUID,
                rewardID: UUID,
                points: Int = 0,
                redeemedAt: Date = .now) {
        self.id = id
        self.kidID = kidID
        self.rewardID = rewardID
        self.points = points
        self.redeemedAt = redeemedAt
    }

    public convenience init(snapshot: RewardRedemptionSnapshot) {
        self.init(id: snapshot.id,
                  kidID: snapshot.kidID,
                  rewardID: snapshot.rewardID,
                  points: snapshot.points,
                  redeemedAt: snapshot.redeemedAt)
    }

    public var snapshot: RewardRedemptionSnapshot {
        RewardRedemptionSnapshot(id: id,
                                 kidID: kidID,
                                 rewardID: rewardID,
                                 points: points,
                                 redeemedAt: redeemedAt)
    }
}

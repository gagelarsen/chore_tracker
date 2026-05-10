import Foundation

/// Discriminator stored on every `Event` record so the audit log can be
/// filtered without decoding `payload`.
///
/// Cases are added phase by phase; Phase 1 covers the MVP loop.
public enum EventType: String, Codable, Hashable, Sendable {
    case choreCompleted
    case awardGiven
    case rewardRedeemed
    case dayClosed
}

/// Strongly-typed payload for every `Event`.
///
/// The append-only `Event` log is the audit trail for every state change.
/// Encoding this as a Codable enum (rather than `[String: Any]`) means the
/// rules engine and tests work with typed cases, while persistence stores it
/// as JSON bytes — no SwiftData transformer quirks with associated-value
/// enums to worry about.
public enum EventPayload: Codable, Hashable, Sendable {
    case choreCompleted(instanceID: UUID, points: Int)
    case awardGiven(points: Int)
    case rewardRedeemed(rewardID: UUID, redemptionID: UUID, points: Int)
    case dayClosed(previousBalance: Int)

    /// Matches the `EventType` discriminator on the persisted record.
    public var type: EventType {
        switch self {
        case .choreCompleted: return .choreCompleted
        case .awardGiven: return .awardGiven
        case .rewardRedeemed: return .rewardRedeemed
        case .dayClosed: return .dayClosed
        }
    }
}

import Foundation

/// Reasons `RulesEngine.applyChoreCompletion` can refuse.
public enum ChoreCompletionError: Error, Equatable, Sendable {
    case instanceNotFound
    case alreadyCompleted
    case kidNotFound
}

/// Reasons `RulesEngine.applyAward` can refuse.
///
/// `points` may be negative (parents can dock for misbehavior) but the
/// resulting balance must remain non-negative — daily balance is a real
/// quantity, not a debt counter.
public enum AwardError: Error, Equatable, Sendable {
    case kidNotFound
    case wouldGoNegative
}

/// Reasons `RulesEngine.redeemReward` can refuse.
public enum RedemptionError: Error, Equatable, Sendable {
    case kidNotFound
    case rewardNotFound
    case rewardInactive
    case insufficientBalance
}

/// Reasons `RulesEngine.closeOutDay` can refuse.
///
/// Empty in Phase 1 (the stub form always succeeds). Phase 3 will add
/// cases such as `.allocationsExceedBalance` once allocation arguments
/// land. The enum is declared now so the engine signature stays stable
/// across phases.
public enum CloseOutError: Error, Equatable, Sendable {
    // Intentionally empty — future cases land in Phase 3.
}

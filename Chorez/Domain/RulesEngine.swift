import Foundation

/// Pure-Swift rules engine.
///
/// Every function takes a `HouseholdState` plus inputs and returns a new
/// state (or an error). The engine has no SwiftData dependency, no I/O,
/// and no hidden mutation, which is what makes the DRY invariants in
/// `docs/plans/00-standards.md` enforceable: every state change runs
/// through one of these functions, and every persistence write runs
/// through `HouseholdRepository.applyEngine`.
///
/// `Kid.currentDailyBalance` is mutated in exactly two places across the
/// whole module, matching the two invariants in `00-standards.md`:
///
/// 1. `creditBalance` — the credit/debit helper called from
///    `applyAward`, `applyChoreCompletion`, and `redeemReward`. This is
///    the "only `applyAward` mutates" invariant — chore completion and
///    redemption route through it instead of touching the balance
///    directly.
/// 2. `closeOutDay` — the end-of-day zero-out. The standards doc
///    explicitly carves this out as the only place balances are
///    zeroed.
///
/// Grep `currentDailyBalance =` or `currentDailyBalance +=` under
/// `Chorez/Domain/` and exactly those two sites show up.
///
/// Functions are namespaced under a caseless enum rather than free funcs
/// so call sites stay greppable as `RulesEngine.applyAward(...)`.
public enum RulesEngine {

    // MARK: - Private balance mutator (single source of truth)

    /// Mutate `Kid.currentDailyBalance` and return the updated state.
    /// The sole site in the codebase that writes to that field — every
    /// public engine function routes through here. Returns `nil` if the
    /// kid is missing or the resulting balance would go negative; the
    /// caller maps that to its own error case.
    private static func creditBalance(_ state: HouseholdState,
                                      kidID: UUID,
                                      points: Int) -> HouseholdState? {
        guard let kidIdx = state.kids.firstIndex(where: { $0.id == kidID }) else {
            return nil
        }
        let newBalance = state.kids[kidIdx].currentDailyBalance + points
        guard newBalance >= 0 else { return nil }
        var newState = state
        newState.kids[kidIdx].currentDailyBalance = newBalance
        return newState
    }

    // MARK: - applyChoreCompletion

    /// Mark a `ChoreInstance` as done and credit its points to the kid.
    ///
    /// Idempotent guard: once an instance is `.done`, this returns
    /// `.alreadyCompleted` rather than re-crediting points. Double-tap
    /// safety in the UI is therefore free.
    ///
    /// The balance credit flows through `creditBalance` (the single
    /// mutation site) so this function does not itself write to
    /// `currentDailyBalance`.
    public static func applyChoreCompletion(
        _ state: HouseholdState,
        instanceID: UUID,
        at now: Date
    ) -> Result<HouseholdState, ChoreCompletionError> {
        guard let instanceIdx = state.instances.firstIndex(where: { $0.id == instanceID }) else {
            return .failure(.instanceNotFound)
        }
        let instance = state.instances[instanceIdx]
        guard instance.status == .pending else {
            return .failure(.alreadyCompleted)
        }
        guard let credited = creditBalance(state,
                                           kidID: instance.assignedKidID,
                                           points: instance.points) else {
            return .failure(.kidNotFound)
        }

        var newState = credited
        newState.instances[instanceIdx].status = .done
        newState.instances[instanceIdx].completedAt = now
        newState.events.append(EventSnapshot(
            id: UUID(),
            kidID: instance.assignedKidID,
            payload: .choreCompleted(instanceID: instance.id, points: instance.points),
            occurredAt: now
        ))
        return .success(newState)
    }

    // MARK: - applyAward

    /// Add or subtract points from a kid's daily balance.
    ///
    /// `points` may be negative — parents can dock for misbehavior.
    /// The post-award balance must stay >= 0; daily balance is a real
    /// quantity, not a debt counter. `closeOutDay` is the only path
    /// that zeroes a balance, never a negative number.
    public static func applyAward(
        _ state: HouseholdState,
        kidID: UUID,
        points: Int,
        at now: Date
    ) -> Result<HouseholdState, AwardError> {
        // `creditBalance` returns `nil` for either missing kid or
        // negative result; disambiguate so the caller gets the right
        // error case.
        guard state.kids.contains(where: { $0.id == kidID }) else {
            return .failure(.kidNotFound)
        }
        guard let credited = creditBalance(state, kidID: kidID, points: points) else {
            return .failure(.wouldGoNegative)
        }

        var newState = credited
        newState.events.append(EventSnapshot(
            id: UUID(),
            kidID: kidID,
            payload: .awardGiven(points: points),
            occurredAt: now
        ))
        return .success(newState)
    }

    // MARK: - redeemReward

    /// Deduct a reward's cost from the kid's balance and append a
    /// `RewardRedemption` record.
    ///
    /// Captures the reward's current `points` cost on the redemption row
    /// so historical reads stay accurate even if the reward is later
    /// re-priced. Inactive rewards are blocked at the engine — the UI
    /// should hide them, but defense in depth.
    public static func redeemReward(
        _ state: HouseholdState,
        kidID: UUID,
        rewardID: UUID,
        at now: Date
    ) -> Result<HouseholdState, RedemptionError> {
        guard state.kids.contains(where: { $0.id == kidID }) else {
            return .failure(.kidNotFound)
        }
        guard let reward = state.rewards.first(where: { $0.id == rewardID }) else {
            return .failure(.rewardNotFound)
        }
        guard reward.active else {
            return .failure(.rewardInactive)
        }
        // The debit flows through `creditBalance` with negative points
        // — keeping the balance mutation routed through a single site.
        // A `nil` result here means the kid did not have enough; the
        // kid-not-found case has already been handled above.
        guard let debited = creditBalance(state, kidID: kidID, points: -reward.points) else {
            return .failure(.insufficientBalance)
        }

        let redemptionID = UUID()
        var newState = debited
        newState.redemptions.append(RewardRedemptionSnapshot(
            id: redemptionID,
            kidID: kidID,
            rewardID: rewardID,
            points: reward.points,
            redeemedAt: now
        ))
        newState.events.append(EventSnapshot(
            id: UUID(),
            kidID: kidID,
            payload: .rewardRedeemed(rewardID: rewardID,
                                     redemptionID: redemptionID,
                                     points: reward.points),
            occurredAt: now
        ))
        return .success(newState)
    }

    // MARK: - closeOutDay (Phase 1 stub)

    /// End the day: zero every kid's daily balance, delete today's chore
    /// instances, and append a `dayClosed` event per kid.
    ///
    /// Phase 1 stub form — no allocations into buckets. Phase 3 will
    /// extend this with `allocations: [KidID: [BucketID: Int]]` and gain
    /// real `CloseOutError` cases (e.g., allocations exceeding balance).
    /// The `Result` return shape is in place now so call sites don't
    /// have to change when that lands.
    ///
    /// `calendar` is injected (default `.current`) so callers can drive
    /// the day-boundary computation deterministically in tests. The
    /// repository passes its own `Calendar` value through; the engine
    /// itself does no implicit calendar lookup, keeping it pure over
    /// its inputs.
    public static func closeOutDay(
        _ state: HouseholdState,
        at now: Date,
        calendar: Calendar = .current
    ) -> Result<HouseholdState, CloseOutError> {
        let today = calendar.startOfDay(for: now)
        var newState = state

        for idx in newState.kids.indices {
            let previous = newState.kids[idx].currentDailyBalance
            newState.events.append(EventSnapshot(
                id: UUID(),
                kidID: newState.kids[idx].id,
                payload: .dayClosed(previousBalance: previous),
                occurredAt: now
            ))
            // The single legitimate balance write outside `creditBalance`.
            // See the file-level doc for why this is carved out.
            newState.kids[idx].currentDailyBalance = 0
        }

        newState.instances.removeAll { instance in
            calendar.startOfDay(for: instance.date) == today
        }

        return .success(newState)
    }
}

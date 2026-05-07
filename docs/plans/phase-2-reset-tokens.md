# Phase 2 — Reset Tokens

> Read [`00-standards.md`](00-standards.md) before starting. Cross-cutting DRY/lint/test/branching rules apply.

## Goal

Add the negative-balance reset-token mechanic. Kids in token debt cannot redeem rewards but can still donate to buckets (foreshadowing Phase 3).

## Scope

- New SwiftData model: `ResetToken`. New denormalized counter on `Kid`: `activeResetTokenCount`.
- Rules engine: new `clearResetToken`. `redeemReward` extended to return `.blockedByResetTokens(count)` when active count > 0.
- UI: "Give Reset Token" action (Home + Kid detail). "Clear Token (5 pts)" action on Kid detail. Reward redemption error sheet listing active tokens.
- Event log entries: `tokenGiven`, `tokenCleared`.

## Files

- `Chorez/Models/ResetToken.swift`
- `Chorez/Repositories/ResetTokenRepository.swift`
- `Chorez/Domain/RulesEngine.swift` (extend)
- `Chorez/Views/Components/TokenBadge.swift`
- `Chorez/Views/Kid/KidDetailView.swift` (extend)
- `Chorez/Views/Kid/RedeemRewardSheet.swift` (extend with blocked state)
- `ChorezTests/RulesEngineTokenTests.swift`
- `ChorezUITests/TokenFlowsUITests.swift`

## DRY guards

- The block check happens only inside `redeemReward`. Views read `Kid.activeResetTokenCount` for display but never duplicate the block logic.
- Token clearing goes only through `clearResetToken`; views don't decrement `activeResetTokenCount` themselves.

## Test plan

- Unit: `clearResetToken` happy path; insufficient-balance error; idempotent re-clear of same token.
- Unit: `redeemReward` returns `.blockedByResetTokens` when count > 0; succeeds when count == 0.
- UI: give a token, attempt to redeem (error sheet shown), clear the token (5 pts spent), redeem succeeds.

## Lint

- `make lint` clean.

## Exit criteria

- [ ] Branch `phase-2-reset-tokens` merged into `main`.
- [ ] CI green.
- [ ] Manual: give 2 tokens, clear one, attempt redemption (still blocked), clear second, redeem succeeds. State and event log are correct.
- [ ] All Phase 2 tests passing alongside all Phase 1 tests.
- [ ] No regressions in Phase 1 flows (full Phase 1 UI suite still green).
- [ ] `make lint` clean with no new disables.

# Phase 3 — Personal Buckets + Close-Out Flow

> Read [`00-standards.md`](00-standards.md) before starting. Cross-cutting DRY/lint/test/branching rules apply.

## Goal

One personal bucket per kid; kid + parent set name and threshold; abandon loses progress; redeem when full. Real close-out flow with split allocation and auto-roll to personal bucket (or loss if no goal).

## Scope

- New model: `PersonalBucket`. `Kid.personalBucketID` populated when active.
- New model: `Donation` (append-only; only personal-bucket donations exist in this phase).
- Rules engine: `donate` (personal-only); full `closeOutDay` taking `allocations`.
- UI: "Set personal goal" sheet on Kid detail (parent enters name + threshold). "Abandon goal" with confirmation. "Redeem personal" when full.
- UI: real Close-Out Day sheet — for each kid with leftover > 0, an allocator with steppers across active buckets (only personal in this phase, but the screen is built to hold N buckets so Phase 4 only adds rows). Sum-must-equal-leftover validation. Auto-roll preview for unallocated.

## Files

- `Chorez/Models/PersonalBucket.swift`, `Donation.swift`
- `Chorez/Repositories/BucketRepository.swift`, `DonationRepository.swift`
- `Chorez/Domain/RulesEngine.swift` (extend `donate`, full `closeOutDay`)
- `Chorez/Views/Components/BucketProgressBar.swift`, `AllocatorRow.swift`
- `Chorez/Views/Kid/KidDetailView.swift` (add personal bucket card)
- `Chorez/Views/Kid/SetPersonalGoalSheet.swift`
- `Chorez/Views/CloseOut/CloseOutDayView.swift`
- `ChorezTests/RulesEngineCloseOutTests.swift`, `RulesEngineDonateTests.swift`
- `ChorezUITests/PersonalBucketUITests.swift`, `CloseOutDayUITests.swift`

## DRY guards

- `AllocatorRow` is generic over bucket type; Phase 4 reuses it for family buckets without modification.
- `BucketProgressBar` works for any bucket type.
- Allocation validation lives in `closeOutDay`; UI just displays errors returned by it.

## Test plan

- Unit: `donate` happy path, locked-bucket rejection (not yet possible for personal but the code path exists for Phase 4), insufficient-balance.
- Unit: `closeOutDay` — even split, uneven split, leftover-with-goal (auto-roll), leftover-without-goal (lost), allocations summing wrong (error).
- Unit: personal bucket abandon clears progress; redeem clears `currentPoints` and stamps `redeemedAt`.
- UI: full flow — set goal, complete chores, close out with split between personal and (mock) leftover, repeat days until full, redeem.

## Lint

- `make lint` clean.

## Exit criteria

- [ ] Branch `phase-3-personal-buckets` merged.
- [ ] CI green.
- [ ] Manual: a kid sets a goal, accumulates over multiple days via close-out, redeems. Another kid abandons mid-progress and loses points (verified in event log).
- [ ] All Phase 1-3 tests green.
- [ ] No regressions in Phase 1-2 flows.
- [ ] `make lint` clean.

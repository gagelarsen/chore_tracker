# Phase 4 — Family Buckets

> Read [`00-standards.md`](00-standards.md) before starting. Cross-cutting DRY/lint/test/branching rules apply.

## Goal

Three family buckets (Adventure / Home / Movie) with donation tracking, locking at threshold, ranked redemption with slot picks. Ties broken by who reached the donation amount first.

## Scope

- New model: `FamilyBucket`. Three rows seeded per household at creation (defaults editable in settings).
- `Donation` model now used for both bucket types.
- Rules engine: `donate` extended for family buckets; `lockBucketIfFull`; `rankBucketDonors`; `redeemFamilyBucket(bucketID, slotPicks)`.
- Slot definitions:
  - Adventure & Home: `dinner`, `dessert`, `activity` (3 slots).
  - Movie: `movieChoice` (1 slot).
- Slot assignment: rank donors; assign top slot to first place, second slot to second place, etc. Empty slots fall through to "Parent picks" (UI shows this; no kid is recorded as the picker).
- Close-out allocator gains family bucket rows (component reused from Phase 3).
- Bucket detail view: leaderboard (rank, total points, time first reached). When locked, "Redeem" opens slot picker.
- Bucket settings: thresholds adjustable per household.

## Files

- `Chorez/Models/FamilyBucket.swift`
- `Chorez/Domain/RulesEngine.swift` (extend `donate`, add `lockBucketIfFull`, `rankBucketDonors`, `redeemFamilyBucket`)
- `Chorez/Domain/SlotChoice.swift`
- `Chorez/Views/Buckets/FamilyBucketDetailView.swift`
- `Chorez/Views/Buckets/RedeemFamilyBucketSheet.swift`
- `Chorez/Views/Buckets/BucketSettingsView.swift`
- `Chorez/Views/CloseOut/CloseOutDayView.swift` (extend with family rows)
- `ChorezTests/RulesEngineFamilyBucketTests.swift`
- `ChorezUITests/FamilyBucketUITests.swift`

## DRY guards

- `donate` handles both personal and family; bucket type discriminated by ID lookup, not a duplicate function.
- `AllocatorRow` and `BucketProgressBar` from Phase 3 are reused as-is.
- Donor ranking is computed in one place (`rankBucketDonors`); the leaderboard UI calls it.

## Test plan

- Unit: `rankBucketDonors` — clear ranking, two-way tie broken by `firstReachedAt`, three-way tie, single donor.
- Unit: `lockBucketIfFull` — exact-threshold, over-threshold via single donation (still locks at exact amount; excess returned to donor's balance per rule below).
- Unit: `donate` to a locked bucket returns `.bucketLocked` error.
- Unit: `redeemFamilyBucket` — fewer kids than slots fills with parent placeholder; correct slots assigned by rank.
- UI: full Adventure cycle — three kids donate unequally over multiple close-outs, bucket fills, locks, parent redeems and assigns slots.

## Lint

- `make lint` clean.

## Open spec question (resolve before implementation)

When a single donation exceeds the remaining bucket capacity, does the excess (a) get refunded to the donor's daily balance, (b) get rejected (donor must split), or (c) get accepted as overflow (bucket goes past 100%)?

**Default assumption:** **(a) refund to donor's daily balance**. Document the chosen rule at the top of the rules engine `donate` function and add a unit test. Confirm with user before merging.

## Exit criteria

- [ ] Branch `phase-4-family-buckets` merged.
- [ ] CI green.
- [ ] Manual: simulate a real Adventure cycle end-to-end on real hardware with 3 kids. Donation counts and slot picks match expectations.
- [ ] All Phase 1-4 tests green.
- [ ] No regressions in earlier phases.
- [ ] `make lint` clean.

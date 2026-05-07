# Standards (apply to every phase)

Cross-cutting rules. Every phase obeys these. PRs that violate them get rejected.

## Branching & PRs (from CLAUDE.md)

- One feature branch per phase: `phase-1-mvp-loop`, `phase-2-reset-tokens`, etc. No direct commits to `main`.
- Each phase ships as one or more PRs into the phase branch, then a single PR from the phase branch into `main` once exit criteria are met.
- Sub-agents create their own branches off the active phase branch; their PRs are reviewed before merge.
- The `superpowers:code-reviewer` agent reviews every sub-agent PR before merge into the phase branch and flags duplication / style drift.

## DRY enforcement (no duplicated logic)

- All point-changing logic lives in `Chorez/Domain/RulesEngine.swift`. View models call it; they do not re-implement it.
- All persistence access goes through `Chorez/Repositories/*Repository.swift`. Views and view models do not touch SwiftData contexts directly.
- Shared SwiftUI components (kid avatar, point pill, bucket progress bar, allocator row, etc.) live under `Chorez/Views/Components/` and are used everywhere they apply. Before adding a new component, search for an existing one.
- Before adding any function, sub-agents must search the codebase for an existing helper that does the job. PR reviewers call out duplication and reject the PR.
- Greppable invariants (recommended pre-merge checks):
  - Only `applyAward` mutates `Kid.currentDailyBalance`.
  - Only `redeemReward` debits balance for a redemption.
  - Only `clearResetToken` decrements `Kid.activeResetTokenCount`.
  - Only `donate` writes `Donation` rows.
  - Only `closeOutDay` zeroes daily balances at end of day.

## Linting

- `make lint` is SwiftLint strict mode. **Zero warnings, zero violations.**
- New SwiftLint disables require an inline justification comment AND mention in the PR description.
- CI fails the build on any lint violation.

## Testing

- Every rules engine function gets unit tests covering: happy path, each error variant, edge cases (zero points, max points, missing entities). Use Swift Testing.
- Every repository gets unit tests against an in-memory SwiftData container.
- Every user-visible flow gets an XCUITest covering the happy path. Critical error paths (reward blocked by token, locked bucket donation, abandoning a personal bucket) get explicit XCUITests.
- `make test` runs the full suite and must pass locally and in CI before any PR merges.
- For bug fixes, write the failing test first (per CLAUDE.md TDD rule).

## Verification before "done"

- Both `make test` and `make lint` pass locally.
- CI green on the phase branch and on the PR into `main`.
- Manual smoke test on a real device for the phase's headline flow.
- Phase exit criteria checklist filled in on the merge PR.

## Architectural baseline (applies across phases)

| Area | Choice |
|---|---|
| UI framework | SwiftUI |
| Persistence | SwiftData (iOS 17+) |
| Sync | CloudKit private DB + `CKShare` |
| Architecture | MVVM with `@Observable` view models; pure-Swift rules engine |
| Tests | Swift Testing for rules + repositories; XCUITest for flows |
| Platforms | iPhone + iPad universal |

## Rules engine surface (cumulative across phases)

The pure-Swift rules engine in `Chorez/Domain/RulesEngine.swift` is the single source of truth for all point math, token math, close-out math, and donation ranking. View models call it; they do not duplicate the rules.

Functions are introduced phase-by-phase:

- `applyChoreCompletion(state, choreID) -> state'` *(P1)*
- `applyAward(state, kidID, points) -> state'` *(P1)*
- `redeemReward(state, kidID, rewardID) -> Result<state', RedemptionError>` *(P1, extended P2 with token block)*
- `clearResetToken(state, kidID) -> Result<state', ClearError>` *(P2)*
- `donate(state, kidID, bucketID, points, at: Date) -> Result<state', DonateError>` *(P3 personal, P4 family)*
- `closeOutDay(state, allocations: [KidID: [BucketID: Int]]) -> Result<state', CloseOutError>` *(P1 stub, P3 full)*
- `rankBucketDonors(donations: [Donation]) -> [(KidID, totalPoints, firstReachedAt: Date)]` *(P4)*
- `lockBucketIfFull(state, bucketID) -> state'` *(P4)*
- `redeemFamilyBucket(state, bucketID, slotPicks: [KidID: SlotChoice]) -> state'` *(P4)*

## Data model (cumulative target)

```
Household        — id, name, ownerCloudUserID, createdAt
Kid              — id, householdID, name, displayOrder, currentDailyBalance,
                   activeResetTokenCount, personalBucketID?
ChoreTemplate    — id, householdID, name, points, assignedKidID,
                   recurrence (.daily for v1), active
ChoreInstance    — id, templateID?, householdID, name, points, assignedKidID,
                   date, status (.pending/.done), completedAt?
Reward           — id, householdID, name, points, active
RewardRedemption — id, kidID, rewardID, points, redeemedAt
ResetToken       — id, kidID, reason?, givenAt, clearedAt?
PersonalBucket   — id, kidID, name, threshold, currentPoints, redeemedAt?
FamilyBucket     — id, householdID, kind (.adventure/.home/.movie),
                   threshold, currentPoints, locked, lastRedeemedAt?
Donation         — id, kidID, bucketID, points, donatedAt   (append-only)
Event            — id, kidID?, type, payload (Codable), occurredAt
                   (append-only audit log)
```

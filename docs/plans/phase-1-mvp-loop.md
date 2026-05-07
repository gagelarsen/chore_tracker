# Phase 1 — MVP Loop

> Read [`00-standards.md`](00-standards.md) before starting. Cross-cutting DRY/lint/test/branching rules apply.

## Goal

A usable parent-only chore tracker on two iPhones, synced via CloudKit. Parents can manage kids, define recurring chores, mark them done, hand out bonuses, define rewards, redeem them, and end the day. No tokens, no buckets yet.

## Scope

- SwiftData `@Model` types: `Household`, `Kid`, `ChoreTemplate`, `ChoreInstance`, `Reward`, `RewardRedemption`, `Event`.
- CloudKit container configured with a `CKShare` flow: owner parent creates the household, generates a share link, spouse joins. Both phones sync read/write from day one.
- Repositories: `HouseholdRepository`, `KidRepository`, `ChoreRepository`, `RewardRepository`, `EventRepository`.
- Rules engine functions (initial set): `applyChoreCompletion`, `applyAward`, `redeemReward` (without token block), `closeOutDay` (stub: zero balances, clear today's chore instances, log events).
- Auto-fill: on first app open of the day, generate today's `ChoreInstance` rows from active `ChoreTemplate` rows.
- Screens: Home (kids + balances), Kid detail (today's chores, redeem reward), Chores manage (templates + ad-hoc), Rewards manage, Settings (with "Invite spouse" share flow).
- Shared components: `KidRow`, `PointPill`, `ChoreCheckbox`. (Other shared components added as needed but documented in this file.)

## Files

- `Chorez/App/ChorezApp.swift`
- `Chorez/Domain/RulesEngine.swift`
- `Chorez/Domain/RulesErrors.swift`
- `Chorez/Models/Household.swift`, `Kid.swift`, `ChoreTemplate.swift`, `ChoreInstance.swift`, `Reward.swift`, `RewardRedemption.swift`, `Event.swift`
- `Chorez/Repositories/HouseholdRepository.swift`, `KidRepository.swift`, `ChoreRepository.swift`, `RewardRepository.swift`, `EventRepository.swift`
- `Chorez/Sync/CloudKitShareCoordinator.swift`
- `Chorez/Views/Home/HomeView.swift`
- `Chorez/Views/Kid/KidDetailView.swift`
- `Chorez/Views/Chores/ChoresManageView.swift`
- `Chorez/Views/Rewards/RewardsManageView.swift`
- `Chorez/Views/Settings/SettingsView.swift`
- `Chorez/Views/Components/KidRow.swift`, `PointPill.swift`, `ChoreCheckbox.swift`
- `ChorezTests/RulesEngineTests.swift`, `RepositoryTests.swift`
- `ChorezUITests/CoreLoopTests.swift`, `ShareFlowUITests.swift`

## DRY guards

- All "award N points to kid" calls go through `applyAward`. Greppable: nothing else should mutate `Kid.currentDailyBalance`.
- "Auto-fill today's chores" lives in one repository method, called from a single app-launch hook.
- Reward redemption deduction goes only through `redeemReward`.

## Test plan

- Unit: every rules function — happy path + each error variant + zero/max edges.
- Unit: each repository against an in-memory SwiftData container — CRUD + auto-fill behaviour.
- UI: end-to-end loop (create kid → create chore template → mark done → redeem → end day).
- UI: share flow on simulator pair (owner generates link, spouse accepts).

## Lint

- `make lint` clean. No new SwiftLint disables.

## Exit criteria (must all be true before Phase 2 starts)

- [ ] Branch `phase-1-mvp-loop` merged into `main` via reviewed PR.
- [ ] CI green on `main`.
- [ ] Two real iPhones (different iCloud accounts) successfully share a household and stay in sync within seconds.
- [ ] Owner parent runs a full day cycle on real hardware: create kids, define templates, complete chores, redeem reward, end day. State is correct after each step.
- [ ] All Phase 1 unit + UI tests passing.
- [ ] `make lint` is clean with zero disables added in this phase.
- [ ] No code duplication flagged by `superpowers:code-reviewer` agent on the merge PR.

# Phase 1.6 — Recurrence patterns + chore editing

> Read [`00-standards.md`](00-standards.md) before starting. Cross-cutting DRY/lint/test/branching rules apply.

## Goal

Stop forcing every chore to recur every day, and let parents fix mistakes in existing chore templates without delete-and-recreate. Two related capabilities; one phase so the data-model change and the edit-sheet UI ship together.

## Scope

### 1. Per-weekday recurrence

- Replace the `Recurrence` enum's single `.daily` case with a struct backed by a 7-bit weekday bitmask (bit `0` = Sunday … bit `6` = Saturday).
- Three preset constructors: `.daily` (127), `.weekdays` (62), `.weekends` (65). Plus a `.custom(Set<Weekday>)` initialiser.
- Add `Weekday` enum modelled on `Calendar.Component.weekday` (Sun=1 … Sat=7), with `bitOffset` and `current` helpers.
- `ChoreRepository.autoFillTodayIfNeeded` checks `template.recurrence.includes(today's weekday)` before spawning the instance. Templates whose pattern doesn't include today are simply skipped — no row, no event.
- `ChoreInstance` itself stays unchanged; its `date` and `status` already capture everything per-day. Only the spawn rule changes.

### 2. Chore template editing

- New "Edit chore" sheet wired from tapping a template row in `ChoresManageView`. Sheet mirrors the existing `AddChoreSheet` layout but pre-fills the fields and the title reads "Edit chore".
- Editable fields: **name, points, assigned kid, recurrence, active toggle**. All five fields are mutable in place.
- Submitting the edit calls `ChoreRepository.updateTemplate(...)`, which:
  - Updates the `ChoreTemplate` row + stamps `updatedAt = .now` + pushes to the sync engine.
  - Cascades to today's **pending** `ChoreInstance` rows for this template: name / points / kid get re-applied so the kid sees the corrected chore immediately. `updatedAt` stamped; sync engine push fires.
  - Cascades to today's pending instances when `active` flips false: the pending row is **deleted** (kid doesn't have to do a chore you just deactivated). Sync push emits a tombstone.
  - **Never** touches completed instances. `Event.choreCompleted` records remain consistent with the historical instance.
- Existing "delete template" path remains under swipe-to-delete on the row; tapping the row body is the edit gesture.

## Files

- `Chorez/Domain/HouseholdState.swift` — replace `enum Recurrence` with a `struct Recurrence` over a `daysOfWeekBitmask: Int`; add `Weekday` enum.
- `Chorez/Domain/RulesEngine.swift` — no engine signature changes; engine doesn't read recurrence.
- `Chorez/Models/ChoreTemplate.swift` — replace `recurrenceRaw: String` with `daysOfWeekBitmask: Int = 127` (default 127 = all days = daily; preserves migration semantics for existing data via property-level default). Update `init(snapshot:)` and `var snapshot`.
- `Chorez/Sync/CKRecordSerializer.swift` — `ChoreTemplateSnapshot.encode` / `init?(record:)` switch from `recurrence` String key to `daysOfWeekBitmask` Int key. CloudKit `Int` is native `CKRecordValue`.
- `Chorez/Repositories/ChoreRepository.swift`:
  - `createTemplate(...)` gains a `recurrence: Recurrence = .daily` parameter.
  - `updateTemplate(...)` gains a `recurrence: Recurrence? = nil` parameter; cascade logic for today's pending instances; tombstone for deletions when active flips false.
  - `autoFillTodayIfNeeded(now:)` filters templates whose recurrence does **not** include `Calendar.current.component(.weekday, from: now)`.
- `Chorez/Views/Chores/ChoresManageView.swift`:
  - Row body becomes a button that opens the new `EditChoreSheet`.
  - Existing add menu unchanged; reuse `ChoreFormFields` for both.
  - Day-of-week picker subview (`WeekdayPicker`) used inside both add and edit sheets.
- `Chorez/Views/Chores/EditChoreSheet.swift` (new) — pre-populated form bound to an existing `ChoreTemplate`.
- `Chorez/Views/Chores/WeekdayPicker.swift` (new) — 7 day toggles + Daily / Weekdays / Weekends preset buttons.
- `ChorezTests/RecurrenceTests.swift` (new) — bitmask round-trip, preset constructors, `includes(weekday:)` truth table.
- `ChorezTests/ChoreRepositoryTests.swift` — auto-fill skips templates whose pattern excludes today; `updateTemplate` cascades to today's pending instance; `updateTemplate(active: false)` deletes today's pending instance; completed instance survives.
- `ChorezTests/CKRecordSerializerTests.swift` — `ChoreTemplateSnapshot` round-trip with non-daily recurrence.
- `ChorezUITests/EditChoreUITests.swift` (new) — happy path: create chore → tap to edit → change name + recurrence → save → verify it appears edited; create chore with Weekdays preset → run on a Saturday-simulated date → instance not spawned. (UI test will need a `-FakeDate=` launch arg for the day-of-week check; covered in test design below.)

## DRY guards

- Recurrence patterns live in one struct (`Recurrence`); no view writes the bitmask directly.
- Today's-pending-instance cascade lives in `ChoreRepository.updateTemplate` only; views call `updateTemplate(...)` and never reach into `ChoreInstance` to mirror changes.
- `WeekdayPicker` is the single component for the day grid in both add and edit sheets.

## Migration

- The default `daysOfWeekBitmask = 127` on the `@Model` covers existing `.daily` templates: when SwiftData hydrates an old row that didn't have the field, it materialises as `127` = every day. No explicit migration step required.
- The previous `recurrenceRaw: String` field is removed. SwiftData will drop it on schema regeneration; for users with on-disk data from before Phase 1.6, a lightweight SwiftData migration (auto-generated when properties change) handles it.
- CloudKit-shared records: the `daysOfWeekBitmask` Int field replaces the `recurrence` String field. Phase 1.5's sync engine pushes the new shape on next write; receivers that read an old shape get the default 127 via the snapshot's `init?(record:)` fallback (the absent key returns nil → snapshot init fails → record is treated as a stale write and the receiver waits for the new shape).

## Test plan

- **Unit**: `RecurrenceTests` covers `.daily.bitmask == 127`, `.weekdays.bitmask == 62`, `.weekends.bitmask == 65`, `Recurrence(daysOfWeekBitmask:).includes(weekday:)` truth table for every (mask, weekday) pair, and Set-based custom constructor.
- **Unit**: `ChoreRepositoryTests` — `autoFillTodayIfNeeded` test with weekday-specific recurrence on a fixed clock; `updateTemplate` cascade on name / points / kid; `updateTemplate(active: false)` tombstone path.
- **Unit**: `CKRecordSerializerTests` — `ChoreTemplateSnapshot` with `.weekends` recurrence round-trips.
- **UI**: `EditChoreUITests` — create-then-edit happy path; the toggle-day-and-verify path needs a deterministic-clock seam (`-FakeDate=YYYY-MM-DD` launch arg parsed in `ChorezApp.init`, threaded through `AppEnvironment.dateProvider`). Cheap to add and useful beyond this phase.

## Lint

- `make lint` clean. No new `// swiftlint:disable` directives.

## Exit criteria

- [ ] Branch `phase-1-6-recurrence` merged into `main` via reviewed PR.
- [ ] CI green on `main`.
- [ ] Manual real-device check: parent creates a chore with `Weekdays` recurrence, completes it Mon-Fri, on Saturday morning today's auto-fill skips it.
- [ ] Manual real-device check: parent taps an existing chore, changes its name + recurrence, hits Save; today's pending instance reflects the new name and re-appears tomorrow only on the new pattern's days.
- [ ] All Phase 1 + 1.5 + 1.6 unit + UI tests passing.
- [ ] `make lint` clean with zero disables added in this phase.
- [ ] No code duplication flagged by the reviewer-agent pass on the merge PR.

## Out of scope (named here so we don't sneak them in)

- "Every N days" / monthly / quarterly cadences — defer until a real use case lands.
- Per-day-different-points (e.g. dishes are 3 points on weekdays but 5 on weekends) — defer.
- Time-of-day reminders ("dishes are due before 8pm") — Phase 5 polish notification work covers the foundation.
- Bulk-edit across kids — defer; parents can swipe-delete and recreate if needed.

# Phase 5 — History, Polish, Conflict Hardening

> Read [`00-standards.md`](00-standards.md) before starting. Cross-cutting DRY/lint/test/branching rules apply.

## Goal

Per-kid history feed, conflict hardening for two simultaneous parent edits, optional close-out reminders, iPad layout, accessibility.

## Scope

- Per-kid event feed under Kid detail (paged, filterable by event type).
- Conflict hardening: idempotent chore completion; guarded family bucket donations near threshold (lock-check inside the same transaction as the write).
- Optional local notification: household-configurable end-of-day reminder.
- iPad: split-view on Home + Kid detail using `NavigationSplitView`.
- Accessibility: VoiceOver labels on all custom controls; Dynamic Type support audit.

## Files

- `Chorez/Views/Kid/KidEventFeedView.swift`
- `Chorez/Views/Settings/NotificationSettingsView.swift`
- `Chorez/Sync/ConflictGuards.swift`
- `Chorez/Views/Home/HomeView.swift` (iPad split adaptation)
- `ChorezTests/ConflictGuardTests.swift`
- `ChorezUITests/EventFeedUITests.swift`, `iPadLayoutUITests.swift`

## DRY guards

- Event feed reuses repositories; no new direct SwiftData queries from the view.
- Conflict guards extend the rules engine rather than wrapping it from outside.

## Test plan

- Unit: conflict guards — concurrent chore-done attempts produce one award, second is a no-op.
- Unit: notification scheduling around DST transitions and silenced hours.
- UI: navigate event feed; filter; iPad split-view layout assertions.
- Two-device manual test: simultaneous chore completion from both phones; only one award appears.

## Lint

- `make lint` clean.

## Exit criteria

- [ ] Branch `phase-5-history-polish` merged.
- [ ] CI green.
- [ ] Two-device concurrent-write test passes on real hardware.
- [ ] All Phase 1-5 tests green.
- [ ] Accessibility audit passes (VoiceOver navigates every screen end-to-end without traps).
- [ ] `make lint` clean.

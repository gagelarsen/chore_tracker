# Chorez Phased Build Plan

Each file in this directory is a self-contained phase definition. Read `00-standards.md` first — it describes cross-cutting rules every phase obeys.

A phase MAY NOT begin until the prior phase's exit-criteria checklist is completed in writing on the merge PR.

## Phases

1. [Phase 1 — MVP Loop](phase-1-mvp-loop.md): kids, chores, rewards, close-out stub, two-parent CloudKit share.
2. [Phase 2 — Reset Tokens](phase-2-reset-tokens.md): negative-balance tokens that block reward redemption.
3. [Phase 3 — Personal Buckets + Close-Out Flow](phase-3-personal-buckets.md): per-kid savings goals, real allocation flow.
4. [Phase 4 — Family Buckets](phase-4-family-buckets.md): Adventure / Home / Movie buckets with ranked donor slot picks.
5. [Phase 5 — History, Polish, Conflict Hardening](phase-5-history-polish.md): event feed, two-parent edge cases, notifications, iPad, accessibility.

## Standards (apply to all phases)

- [00 — Standards](00-standards.md): DRY, lint, tests, branching, rules-engine surface, data model.

## Architectural baseline

- SwiftUI + SwiftData on iOS 17+
- CloudKit private DB + `CKShare` for two-parent sync
- Pure-Swift rules engine in `Chorez/Domain/` is the single source of truth for all point math
- Repository layer wraps SwiftData; views never touch contexts directly
- SwiftLint strict, zero violations; Swift Testing for unit; XCUITest for flows

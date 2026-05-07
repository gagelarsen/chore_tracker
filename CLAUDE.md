# CLAUDE.md — Chorez Project Policies

These rules apply to anyone (human or agent) making changes to this
repository. They override generic best-practice defaults when they conflict.

## 1. Branch hygiene

- **Never commit directly to `main`.** Always work on a feature branch and
  open a PR.
- Branches should be short-lived. Rebase or merge `main` regularly.
- Sub-agents create their own branches off the current branch and request
  review before merging back.

## 2. TDD for bug fixes

When fixing a bug:

1. **Reproduce it with a failing test first.** Commit the failing test (or
   include it in the same commit as the fix — your call) so the regression
   is captured in history.
2. Then write the fix.
3. Confirm the test now passes.

A bug fix without a regression test is rejected unless the bug is
unreachable from a test (rare — say so explicitly in the PR).

## 3. Test coverage

- Every new **public type or function** ships with at least one test.
- Pure SwiftUI `View` types are exempt from unit tests **but** any
  user-reachable view must have UI test coverage of its happy path.
- Tests assert behavior, not implementation. Don't test private internals.
- Prefer **Swift Testing** (`@Test`) for unit tests. Use **XCUITest** for
  UI tests.
- One real assertion minimum per test — no `XCTAssertTrue(true)` shells.

## 4. Documentation

- Every public type and function gets a `///` DocC comment.
- The comment explains **why** the thing exists, not what it does (the
  signature already says what). One line is fine if the purpose is obvious.
- Document non-obvious internal helpers too. If you wouldn't understand it
  in six months, document it now.
- Keep `README.md` accurate. If you add a make target, dependency, or
  setup step, update the README in the same PR.

## 5. Verification before "done"

- Run `make test` locally before pushing. **"Should work" is not done.**
- CI must be green before merge. No bypass merges.
- For UI changes, actually run the app in the simulator and verify the
  feature behaves as described.

## 6. Project file generation

- **Never hand-edit `Chorez.xcodeproj`.** It's gitignored and regenerated
  from `project.yml`.
- All target/scheme/build-setting changes go in `project.yml`.
- After editing `project.yml`, run `make project` and verify the generated
  scheme still builds.

## 7. Dependencies

- Keep dependencies minimal. The standard library, SwiftUI, Foundation, and
  Swift Testing are enough for most things.
- Any new SPM dependency requires a justification in the PR description:
  what it solves, what we considered, why we can't do it ourselves.
- Pin versions exactly. Avoid `from:` ranges that auto-resolve to new
  major versions.

## 8. Linting

- **SwiftLint is the canonical linter.** CI runs `make lint` (which invokes
  `swiftlint --strict`) and fails on any warning or error.
- New code must produce **zero** SwiftLint findings. "Warnings are fine"
  is not fine — strict mode treats warnings as failures.
- If a rule is wrong for this codebase, change `.swiftlint.yml` (with the
  reasoning in the PR description) rather than papering over violations
  with inline `// swiftlint:disable`.
- `// swiftlint:disable` is acceptable when the rule is right but a
  specific call site genuinely needs the exception. Always pair it with a
  comment explaining why and use the narrowest scope possible
  (`// swiftlint:disable:next <rule>` over a file-level disable).
- Run `make lint` before pushing. Same bar as `make test`: "should be
  clean" is not clean.

---

## Quick reference

| Verb | Command |
|---|---|
| Generate Xcode project | `make project` |
| Build the app | `make build` |
| Run all tests | `make test` |
| Run the linter | `make lint` |
| Wipe build artifacts | `make clean` |

## When working with sub-agents

Per the user's global instructions, when farming work to a sub-agent:

1. The sub-agent creates its own branch off the current branch.
2. Before merging the sub-agent's branch back, dispatch the
   `superpowers:code-reviewer` agent (or equivalent reviewer).
3. The review must pass before the merge.

Reviewers should flag: code smells, inconsistencies with surrounding code,
duplicated logic that could reuse existing helpers, and style drift from
established repo patterns.

# Chorez iOS App — Initial Scaffold Design

**Date:** 2026-05-07
**Status:** Approved
**Author:** Gage Larsen (with Claude)

## Goal

Stand up the minimum viable structure for an iOS app named **Chorez** so that
domain work can begin on a known-good foundation. The scaffold must:

1. Build and run a SwiftUI placeholder screen on iOS 17+.
2. Run unit and UI tests locally and in CI on every push.
3. Establish project conventions (testing, documentation, branching) via a
   `CLAUDE.md` policy file that future contributors — human or agent — must
   follow.

This spec covers *only* scaffolding. No domain modeling, persistence, or
chore-tracking features are in scope.

## Non-Goals

- App icon design, branding, or marketing copy.
- TestFlight / App Store distribution (no Fastlane, no provisioning automation).
- Networking, persistence, or analytics layers.
- Linting/formatting tooling beyond what Xcode provides by default. (We can
  add SwiftLint later if patterns drift.)

## Architecture

### Project generation: XcodeGen

The Xcode project file is **generated from `project.yml`** via
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated
`Chorez.xcodeproj` is gitignored. Every change to project structure happens in
`project.yml`.

Rationale:
- Eliminates pbxproj merge conflicts.
- Makes CI deterministic (no stale schemes, no developer-specific paths).
- Keeps `git diff` readable.

Cost: contributors must `brew install xcodegen` and run `make project` after
pulling structural changes. Acceptable for the team size.

### App target

| Setting | Value |
|---|---|
| App name | Chorez |
| Bundle identifier | `com.glarsen.chorez` |
| Deployment target | iOS 17.0 |
| UI framework | SwiftUI |
| Swift version | 5.10 |
| Entry point | `@main struct ChorezApp: App` |

The initial `ContentView` is an intentional placeholder ("Hello, Chorez")
so the first end-to-end test can assert *something* real.

### Test targets

| Target | Framework | Purpose |
|---|---|---|
| `ChorezTests` | Swift Testing (`@Test`) | Unit tests for non-UI code |
| `ChorezUITests` | XCUITest | Launch + smoke UI assertions |

Each target ships with one **non-trivial** sample test so a green CI run
proves real test execution rather than zero-test success.

## Repository Layout

```
.
├── Chorez/
│   ├── ChorezApp.swift
│   ├── ContentView.swift
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/
│   │   └── AccentColor.colorset/
│   └── Info.plist
├── ChorezTests/
│   └── ChorezTests.swift
├── ChorezUITests/
│   └── ChorezUITests.swift
├── .github/workflows/ci.yml
├── docs/superpowers/specs/
├── project.yml
├── Makefile
├── .gitignore
├── .swift-version
├── CLAUDE.md
└── README.md
```

## CI

GitHub Actions workflow at `.github/workflows/ci.yml`:

- **Runner:** `macos-14` (ships with Xcode 15.4 and iOS 17 simulators).
- **Triggers:** `push` to any branch, `pull_request` targeting `main`.
- **Steps:**
  1. `actions/checkout@v4`
  2. Select Xcode: `sudo xcode-select -s /Applications/Xcode_15.4.app`
     (with a fallback `xcodebuild -version` debug print).
  3. Install XcodeGen: `brew install xcodegen`
  4. Generate project: `xcodegen generate`
  5. Build & test: `xcodebuild test -scheme Chorez -destination "platform=iOS Simulator,name=iPhone 15" -resultBundlePath build/Chorez.xcresult | xcpretty`
  6. On failure, upload `build/Chorez.xcresult` as an artifact.
- **Caching:** DerivedData cached on `project.yml` hash to speed reruns.

## Local Developer Workflow

A `Makefile` exposes the common verbs:

```
make project   # xcodegen generate
make build     # xcodebuild build
make test      # xcodebuild test (the same command CI runs)
make clean     # rm -rf build/ and the generated .xcodeproj
```

`make test` is the canonical "did I break it?" check. CLAUDE.md requires it
to pass before any push.

## Policies (CLAUDE.md)

The committed `CLAUDE.md` codifies seven rules. Each is enforceable by either
a reviewer or a CI step.

1. **Branch hygiene.** Never commit directly to `main`. Feature branches
   only. CI runs on PRs into `main`.
2. **TDD for bug fixes.** A bug fix must include a failing regression test
   *committed before* (or in the same commit as) the fix.
3. **Test coverage.** Every new public type or function ships with at least
   one test. Pure SwiftUI views are exempt from unit tests but must be
   covered by a UI test if user-reachable.
4. **Documentation.** Every public type and function gets a `///` DocC
   comment that explains *why* it exists (one line is fine if obvious).
   Internal helpers documented only when non-obvious.
5. **Verification before done.** `make test` passes locally before pushing.
   CI green before merge. "Should work" is not done.
6. **Project file generation.** Never hand-edit `Chorez.xcodeproj`. Change
   `project.yml` and run `make project`.
7. **Dependencies.** Keep them minimal. Any new SPM dep needs a justification
   line in the PR description.

## Testing Strategy

- **Unit:** Swift Testing (`@Test func ...`). Async-friendly, less ceremony
  than XCTest. Use parameterized tests where helpful.
- **UI:** XCUITest. One smoke test confirms the app launches and the
  placeholder text appears.
- **No mocking framework yet.** Hand-rolled test doubles until a real need
  emerges; YAGNI.

## Risks & Open Questions

- **Xcode version drift on `macos-14` runners.** GitHub may bump the default
  Xcode. Pinning explicitly via `xcode-select` mitigates this; we'll monitor
  CI for surprises.
- **Swift Testing maturity.** Stable in Xcode 16+, supported in Xcode 15.4.
  If we hit edge cases on the runner's Xcode, we fall back to XCTest for
  unit tests.
- **No app icon yet.** Xcode 15+ tolerates an empty `AppIcon` set in
  development. Before any TestFlight build we must add real icons.

## Implementation Order

1. `.gitignore`, `.swift-version`, `Makefile`
2. `project.yml`
3. App sources (`ChorezApp.swift`, `ContentView.swift`, `Assets.xcassets`,
   `Info.plist`)
4. Test sources (unit + UI)
5. `make project` and verify it generates a working `.xcodeproj`
   *(requires xcodegen installed locally)*
6. `make test` and verify it passes
7. `.github/workflows/ci.yml`
8. `CLAUDE.md`
9. Update `README.md` with setup instructions
10. Commit on the existing `gagelarsen/sofia` branch (do not rename)

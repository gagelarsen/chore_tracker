# Chorez

An iOS app for tracking chores. This repository currently holds the project
scaffold — the chore-tracking features are still to come.

## Prerequisites

- macOS with **Xcode 16** or newer — required for the iPhone 16/17
  simulators that `make` and CI default to.
- **XcodeGen** (`brew install xcodegen`) — generates the Xcode project from
  `project.yml`.
- **SwiftLint** (`brew install swiftlint`) — required by `make lint` and CI.

### For CloudKit / real-device builds only

- A paid **Apple Developer Program** membership (free Apple IDs cannot use
  CloudKit). Find your 10-character team ID at
  https://developer.apple.com/account → Membership.
- A local `.chorez-team.local` file in the repo root (gitignored) with one
  line:

  ```sh
  CHOREZ_TEAM_ID=YOUR10CHRID
  ```

  `make project` reads this and substitutes the team ID into the generated
  Xcode project's `DEVELOPMENT_TEAM` setting and CloudKit entitlement. The
  file is git-ignored so the ID never leaves your machine. CI builds with
  `CODE_SIGNING_ALLOWED=NO`, so missing the file does not break the CI
  pipeline; it only matters for signed builds (real devices and TestFlight).
- The CloudKit container `iCloud.com.glarsen.chorez` auto-provisions on
  first signed build with the entitlement. Inspect or pre-configure it at
  https://icloud.developer.apple.com/dashboard.

## Getting started

```sh
# 0. (CloudKit only) Drop your team ID into a local file
echo 'CHOREZ_TEAM_ID=YOUR10CHRID' > .chorez-team.local

# 1. Generate the Xcode project
make project

# 2. Open it in Xcode (optional — Make targets cover most workflows)
open Chorez.xcodeproj

# 3. Build and run all tests
make test
```

## Project layout

```
Chorez/            App sources (SwiftUI, iOS 17+)
ChorezTests/       Unit tests (Swift Testing)
ChorezUITests/     UI tests (XCUITest)
project.yml        XcodeGen project spec — edit this, never the .xcodeproj
Makefile           Common dev verbs (project / build / test / lint / clean)
.swiftlint.yml     SwiftLint configuration
.github/workflows  GitHub Actions CI
docs/              Design specs and project documentation
CLAUDE.md          Repo policies (testing, docs, branching, deps)
```

## Make targets

| Target | What it does |
|---|---|
| `make project` | Run `xcodegen generate` to produce `Chorez.xcodeproj`. |
| `make build`   | Build the Chorez scheme for an iOS simulator (iPhone 17 by default — override with `DESTINATION=...`). |
| `make test`    | Run unit and UI tests. The same command CI runs. |
| `make lint`    | Run SwiftLint over the sources (strict mode — warnings fail). |
| `make clean`   | Remove build artifacts and the generated project. |

## CI

GitHub Actions runs `make lint` and `make test` against an `iPhone 16`
simulator (on a `macos-15` runner) on every push and on PRs into `main`.
See `.github/workflows/ci.yml`.

## Conventions

Read [`CLAUDE.md`](./CLAUDE.md) before contributing. It's the source of
truth for branching, testing, documentation, and dependency rules.

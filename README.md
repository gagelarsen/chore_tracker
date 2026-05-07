# Chorez

An iOS app for tracking chores. This repository currently holds the project
scaffold — the chore-tracking features are still to come.

## Prerequisites

- macOS with **Xcode 15.4** (or newer Xcode that ships an iOS 17 simulator)
- **XcodeGen** (`brew install xcodegen`) — generates the Xcode project from
  `project.yml`

## Getting started

```sh
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
Makefile           Common dev verbs (project / build / test / clean)
.github/workflows  GitHub Actions CI
docs/              Design specs and project documentation
CLAUDE.md          Repo policies (testing, docs, branching, deps)
```

## Make targets

| Target | What it does |
|---|---|
| `make project` | Run `xcodegen generate` to produce `Chorez.xcodeproj`. |
| `make build`   | Build the Chorez scheme for an iOS 17 simulator. |
| `make test`    | Run unit and UI tests. The same command CI runs. |
| `make clean`   | Remove build artifacts and the generated project. |

## CI

GitHub Actions runs `make test` against an `iPhone 15` simulator on every
push and on PRs into `main`. See `.github/workflows/ci.yml`.

## Conventions

Read [`CLAUDE.md`](./CLAUDE.md) before contributing. It's the source of
truth for branching, testing, documentation, and dependency rules.

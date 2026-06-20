# Contributing to VSSwift

First off — thanks for taking a look! 🎉

VSSwift is a **fun, vibe-coded** macOS code editor experiment. It is **not** intended
for production use, so contributions are welcome in the same spirit: curious,
experimental, and friendly.

## Ground rules

- Be kind. See the [Code of Conduct](./CODE_OF_CONDUCT.md).
- Keep the layered architecture intact (see the SPM module map in the [README](./README.md)).
  Dependencies flow **downward only**; a lower layer must never import a higher one.
- All targets compile under **Swift 6 strict concurrency** (`.swiftLanguageMode(.v6)`).
- Expensive work runs on **actors**; results hop to `@MainActor` for UI.

## Getting set up

```bash
git clone https://github.com/avijeetpandey/VSSwift.git
cd VSSwift
./run.sh --build-only      # first build fetches swift-syntax (~3 min)
./run.sh                   # build + launch
./run.sh --test            # run every package's test suite
```

> The sandboxed dev environment injects git config that breaks SwiftPM dependency
> resolution. Every swift command in this repo is prefixed with `GIT_CONFIG_COUNT=0`
> (already handled by `run.sh`).

## Formatting & linting

We use [swift-format](https://github.com/swiftlang/swift-format) (ships with the
toolchain) and, optionally, [SwiftLint](https://github.com/realm/SwiftLint).

```bash
./run.sh --format          # apply swift-format in place
./run.sh --lint            # check formatting without writing
swiftlint                  # optional, if installed (brew install swiftlint)
```

Formatting is **advisory** — CI will not block a PR on style. Please run it before
opening a PR anyway to keep diffs tidy.

## Tests

Because the project targets a Command-Line-Tools-only environment (no XCTest), each
package ships an executable test target backed by the custom **VSTestKit** harness.
Add cases to the relevant `TestMain.swift` and ensure `./run.sh --test` stays green.

## Pull requests

- Branch from `main`, keep PRs focused, and write a clear description.
- Reference any related issues.
- Make sure `./run.sh --build-only` and `./run.sh --test` pass.

Have fun! ✨

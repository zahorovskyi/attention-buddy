# Contributing

Thanks for helping. Issues and pull requests are welcome.

## Setup

- macOS 13 or later with Xcode (for Swift Testing and `swift-format`)
- `brew install jq shellcheck bats-core gitleaks`

## Build and run

```bash
swift build
.build/debug/attention-buddy              # run the icon from your checkout
.build/debug/attention-buddy snapshot /tmp/icons
```

To try your changes with real Claude Code sessions, install from your clone: `./install.sh`.
Running it again rebuilds the app and restarts the icon.

## Checks

Run everything CI runs before opening a pull request (`swift format format -i -r Sources Tests
Package.swift` fixes formatting):

```bash
swift format lint --strict -r Sources Tests Package.swift
swift test
scripts/build.sh
shellcheck -s sh install.sh scripts/*.sh hooks/*.sh
bats ShellTests
scripts/check-privacy.sh
claude plugin validate .
```

## Guidelines

- Read [docs/DESIGN.md](docs/DESIGN.md) first. Update it when you change behavior.
- Keep logic in `AttentionCore` (no AppKit) and cover it with Swift tests.
- Cover hook and installer changes with bats tests.
- The hook script runs on every tool call: keep it silent, safe and fast.
- No personal data in commits: no real home paths, emails or machine details. To also block
  personal words (names, company terms), list them one per line in a git-ignored
  `.privacy-denylist` file; `scripts/check-privacy.sh` checks them too.
- Note every user-visible change under `## [Unreleased]` in `CHANGELOG.md`, and update
  `README.md`, `docs/DESIGN.md` and `AGENTS.md` when behavior changes.

## Releasing

1. Set the version in `Sources/AttentionCore/Version.swift` and `.claude-plugin/plugin.json`, and
   rename `## [Unreleased]` in `CHANGELOG.md` to `## [X.Y.Z] - <date>` (a test checks they match).
2. Commit, tag `vX.Y.Z`, push the commit and the tag, and create a GitHub release with that
   changelog section as its notes.
3. In the tap repository, update `Formula/attention-buddy.rb` with the new tag URL and its
   `sha256` (`curl -fsSL https://github.com/zahorovskyi/attention-buddy/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`),
   then push.
4. Check that CI passes in both repositories; the tap's CI builds the new release from source.

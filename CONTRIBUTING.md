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

## Checks

Run everything CI runs before opening a pull request:

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
- No personal data in commits: no real home paths, emails or machine details.

## Releasing

1. Update the version in `Sources/AttentionCore/Version.swift`, `.claude-plugin/plugin.json` and
   `CHANGELOG.md` (a test checks they match).
2. Commit, tag `vX.Y.Z`, push the tag and create a GitHub release.
3. In the tap repository, update `Formula/attention-buddy.rb` with the new tag URL and its
   `sha256` (`curl -fsSL <tarball-url> | shasum -a 256`).

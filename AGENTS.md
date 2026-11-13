# AGENTS.md

Instructions for AI coding agents. Humans: see [README.md](README.md).

## What this project is

Attention Buddy is a small macOS app that shows a floating, draggable Claude Code mascot on the
desktop. It watches every Claude Code session through Claude Code hooks and changes when a session
needs the user: red, blinking, jumping and waving for an approval or question, green when a turn
is done. It is silent, uses no network, and stores no prompt or code content.

Architecture in one line: Claude Code hook events → `hooks/attention-buddy-hook.sh` writes
`~/.claude/attention-buddy/<session_id>.json` → the Swift app polls those files and animates the
icon. Full design: [docs/DESIGN.md](docs/DESIGN.md).

## Helping a user install it

Check the requirements first:

```bash
sw_vers -productVersion        # needs 13 or later
xcode-select -p                # Command Line Tools present? If not: xcode-select --install
command -v jq                  # present on macOS 15+; otherwise: brew install jq
```

Then help the user pick one method:

| If the user… | Use | Commands |
| --- | --- | --- |
| mainly uses Claude Code and wants no terminal | Claude Code plugin | In Claude Code: `/plugin marketplace add zahorovskyi/attention-buddy`, then `/plugin install attention-buddy@attention-buddy` |
| uses Homebrew | Homebrew | `brew install zahorovskyi/tap/attention-buddy`, `attention-buddy setup`, `brew services start attention-buddy` |
| wants it running from login, no Homebrew | Install script | `curl -fsSL https://raw.githubusercontent.com/zahorovskyi/attention-buddy/main/install.sh \| sh` |
| wants to read or change the code | Clone | `git clone https://github.com/zahorovskyi/attention-buddy.git && cd attention-buddy && ./install.sh` |

Only one method is needed. Installing twice is harmless but `doctor` warns about it.

Before running the install script, tell the user what it changes (offer `--dry-run` to show it):

- installs `~/.local/bin/attention-buddy` and `~/.local/share/attention-buddy/`
- adds hook entries to `~/.claude/settings.json`, after saving a timestamped backup next to it
- adds a login item: `~/Library/LaunchAgents/io.github.zahorovskyi.attention-buddy.plist`
- the app writes small state files to `~/.claude/attention-buddy/`

**Verify** after installing:

```bash
attention-buddy doctor     # exit code 0 means connected; "✗" lines explain what is missing
```

For the plugin, `doctor` is not on the PATH; check that the icon appears after starting a new
Claude Code session (the first start builds it, about 10 seconds).

**Uninstall:**

- Plugin: `/plugin uninstall attention-buddy`, then quit the icon (right-click → Quit).
- Install script: `sh ~/.local/share/attention-buddy/install.sh --uninstall`
- Homebrew: `attention-buddy setup --remove && brew services stop attention-buddy && brew uninstall attention-buddy`

**If it does not react:** run `attention-buddy doctor`. Common causes are missing hooks,
an organization policy that allows only managed hooks, or a missing `jq`.

## Working on the code

Layout:

```
Sources/AttentionCore/     pure logic, no AppKit (state files, priority, seen timer, scheduler, doctor)
Sources/AttentionUI/       AppKit + Core Animation (window, icon layers, animations, app controller)
Sources/attention-buddy/   command-line entry point (run, setup, doctor, snapshot)
Tests/                     Swift Testing suites
hooks/                     the hook script and the plugin's hooks.json
scripts/                   build.sh (plain swiftc build), plugin-start.sh, check-privacy.sh
ShellTests/                bats tests for the hook script, installer and plugin
install.sh                 installer for the one-line and clone methods; also used by `setup`
.claude-plugin/            plugin manifest and marketplace file
```

Commands (Xcode for Swift Testing and swift-format; `brew install shellcheck bats-core gitleaks`):

```bash
swift build                                  # debug build
swift test                                   # Swift tests
bats ShellTests                              # shell tests
scripts/build.sh                             # the build installers use (plain swiftc)
swift format lint --strict -r Sources Tests Package.swift
shellcheck -s sh install.sh scripts/*.sh hooks/*.sh
scripts/check-privacy.sh                     # no personal data in the repository
claude plugin validate .                     # plugin and marketplace files
```

Rules:

- Keep `AttentionCore` free of AppKit. Inject clocks, file locations and process checks so logic
  stays testable.
- Swift 6 language mode; UI code is `@MainActor`. No force unwraps, no third-party dependencies.
- Prefer explicit, readable code over clever operators.
- Shell scripts are POSIX `sh`, `shellcheck` clean, with every variable quoted.
- The hook script must never print, never fail and stay fast; it runs on every tool call.
- Every new event or state needs tests (Swift and bats) and an update to `docs/DESIGN.md`.
- Never commit personal data: no real home paths, emails or machine details.
  `scripts/check-privacy.sh` enforces this in CI.
- Versions must match in `Sources/AttentionCore/Version.swift`, `.claude-plugin/plugin.json` and
  `CHANGELOG.md` (tested).

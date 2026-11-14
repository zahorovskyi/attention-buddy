# AGENTS.md

Instructions for AI coding agents. Humans: see [README.md](README.md).

## What this project is

Attention Buddy is a small macOS app that shows a floating, draggable Claude Code mascot on the
desktop. It watches every Claude Code session through Claude Code hooks and changes when a session
needs the user: red, blinking, jumping and waving for an approval or question, green when a turn
is done. It is silent, uses no network, and stores no prompt or code content.

Architecture in one line: Claude Code hook events → `hooks/attention-buddy-hook.sh` writes
`~/.claude/attention-buddy/<session_id>.json` → the Swift app watches that folder and animates the
icon. Full design: [docs/DESIGN.md](docs/DESIGN.md).

## Explaining it to a user

- **States:** dim clay and stepping while Claude works; red, blinking, jumping and waving when a
  session needs an approval, an answer or MCP input; steady red ("seen") once the user looked
  (switched to Claude or clicked the icon), back to blinking after 3 minutes; green with a hop when a turn is done; red with a head
  shake when a turn failed; grey with closed eyes and drooping arms while the user put it to
  sleep. With several sessions it shows the most urgent one.
- **Using it:** drag it anywhere (it starts at the bottom-right corner, above the Dock); hover or
  click it to open a card listing every session and what it needs; click a session in the card to
  open exactly that session in the Claude desktop app (terminal sessions are listed but can't be
  opened); in the card, dots of sessions that need you blink red; right-click for Show waiting sessions, Mark all as seen, Forget all sessions,
  Sleep, Wake up (while asleep), Settings…, About, Hide until next session and Quit.
- **Sleep:** the slider at the bottom of the card (or right-click → Sleep) silences the icon for
  15, 30 or 45 minutes, 1, 2 or 4 hours, or until midnight. It wakes up by itself or with Wake up,
  then shows the real state. Sessions keep being tracked meanwhile.
- **Settings…:** an icon size slider from 1× (smallest) to 4× (new installs start at 2×), a card
  size slider from 1× to 2× (the card and its sleep slider), and a checkbox to hide the sleep
  slider (hiding it also wakes the icon). Advanced timings
  (`seenTimeout`, `repeatInterval`) are `defaults write io.github.zahorovskyi.attention-buddy …`
  values; see the README.
- **Privacy:** no network access; only the event name, session id, tool name, folder and session
  title are stored, never prompts, code or output. To open sessions and show their current names,
  it reads (never changes) the desktop app's session list in
  `~/Library/Application Support/Claude/claude-code-sessions/`, using only the session ids and
  titles.

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

For the plugin, the app is not on the `PATH`. Start a new Claude Code session (the first start
builds the icon, about 10 seconds), then run
`~/.claude/plugins/data/attention-buddy-attention-buddy/bin/attention-buddy doctor`.

**Uninstall:**

- Plugin: `/plugin uninstall attention-buddy`, then quit the icon (right-click → Quit).
- Install script: `sh ~/.local/share/attention-buddy/install.sh --uninstall`
- Homebrew: `attention-buddy setup --remove && brew services stop attention-buddy && brew uninstall attention-buddy`
- The install script also deletes the state folder and preferences. For the plugin or Homebrew,
  offer to remove them: `rm -rf ~/.claude/attention-buddy` and
  `defaults delete io.github.zahorovskyi.attention-buddy`.

**Updating:** plugin: `claude plugin marketplace update attention-buddy` then
`claude plugin update attention-buddy@attention-buddy`; one-line install: rerun it; clone:
`git pull && ./install.sh`; Homebrew: `brew update && brew upgrade attention-buddy`. The running
icon switches to the new version by itself; nothing to restart.

**Closing the icon:** "Hide until next session" (right-click menu) returns with the next Claude
Code session; "Quit" stays closed until the user next logs in (plugin installs: until a restart).
Start it by hand, which also ends a Quit, with `/attention-buddy:start` in Claude Code (plugin),
`attention-buddy` or `launchctl kickstart gui/$(id -u)/io.github.zahorovskyi.attention-buddy`
(install script) or `brew services restart attention-buddy` (Homebrew). Restarting Claude Desktop
doesn't start it.

**If it does not react:** run `attention-buddy doctor`. Common causes are missing hooks,
an organization policy that allows only managed hooks, or a missing `jq`.

## Working on the code

Layout:

```
Sources/AttentionCore/     pure logic, no AppKit: state files, priority, seen timer, sleep, animation scheduler,
                           settings and size range, placement, card content and open/close rules,
                           desktop session ids, titles and links, Quit note, update detection,
                           single-instance lock, doctor
Sources/AttentionUI/       AppKit + Core Animation: floating window, icon layers and animations, session card, sleep slider,
                           Settings window, state folder watcher, app controller, PNG snapshots
Sources/attention-buddy/   command-line entry point (run, setup, doctor, snapshot)
Tests/                     Swift Testing suites
hooks/                     the hook script and the plugin's hooks.json
skills/start/              the plugin's /attention-buddy:start command
scripts/                   build.sh (plain swiftc build), plugin-start.sh, check-privacy.sh
ShellTests/                bats tests for the hook script, installer, plugin and repository checks
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
- Menu item actions get neutral names (never `openSettings`, `showPreferences` and the like):
  macOS 26 adds icons to items with standard-looking action names, which misaligns the menu.
- Shell scripts are POSIX `sh`, `shellcheck` clean, with every variable quoted.
- The hook script must never print, never fail and stay fast; it runs on every tool call.
- Installers replace files by copy to a temporary file plus `mv`, never by overwriting in place:
  macOS kills a binary rewritten in place while a copy of it runs.
- Every new event or state needs tests (Swift and bats) and an update to `docs/DESIGN.md`.
- When user-visible behavior changes, update `README.md`, `docs/DESIGN.md`, this file and the
  `[Unreleased]` section of `CHANGELOG.md` in the same change.
- Never commit personal data: no real home paths, emails or machine details.
  `scripts/check-privacy.sh` enforces this in CI.
- Versions must match in `Sources/AttentionCore/Version.swift`, `.claude-plugin/plugin.json` and
  `CHANGELOG.md` (tested).

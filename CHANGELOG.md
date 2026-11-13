# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org).

## [0.1.3] - 2026-11-13

- The right-click menu no longer shows a gear next to "Settings…", so all items line up.
- `doctor` now explains how to start the icon again for each install method.
- Documentation: how to restart the icon after Quit, `doctor` for plugin installs, the
  preferences file, cleaning up after a plugin or Homebrew uninstall, and a full list of
  preferences, interactions and tests in the design doc.

## [0.1.2] - 2026-11-13

- Settings window, opened from the right-click menu, with an icon size slider from 1× (the
  original size) to 4×. The icon resizes live, grows away from its nearest screen corner so it
  stays in place, and remembers its size.

## [0.1.1] - 2026-11-13

- The right-click menu now holds only actions; the sessions are listed in the hover card.
- New "About Attention Buddy" menu item that opens the project page.
- The icon now starts near the bottom-right corner of the screen, above the Dock.

## [0.1.0] - 2026-11-13

First release.

- Floating, draggable Claude Code mascot that shows five states: working, needs you, seen, done
  and error, with animations and a Reduce Motion fallback.
- Hook script that records each session's state from Claude Code hook events, including
  approvals, questions and MCP input requests.
- "Seen" state with a 3-minute timeout once you look at Claude.
- Click to open Claude's waiting sessions; right-click menu with every session.
- `attention-buddy setup`, `doctor` and `snapshot` commands.
- Four install methods: Claude Code plugin, one-line install, clone and Homebrew.

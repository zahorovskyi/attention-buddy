# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.9] - 2026-11-14

- Sleep: a slider at the bottom of the session card puts the buddy to sleep for 15, 30 or 45
  minutes, 1, 2 or 4 hours, or until midnight. Asleep it is grey with closed eyes, drooping arms,
  slow breathing and a floating "z", and stays silent while sessions keep being tracked. It wakes
  up by itself, with the card's Wake up button or from the right-click menu (new Sleep and Wake
  up items), then shows the real state. A sleep survives a restart and a Quit.
- Settings: a card size slider (1× to 2×) that scales the session card and its sleep slider, and
  a checkbox to hide the sleep slider (hiding it also wakes the buddy).
- The session card keeps a fixed width, so it no longer changes size when its summary grows.
- README: the state picture adds Asleep, and the card and desktop pictures show the sleep slider.

## [0.1.8] - 2026-11-14

- Fix: the session card showed small light square corners when open over a light window.
- Documentation: the Install and "What it changes" tables say the icon also starts with each
  Claude Code session for script and Homebrew installs; the design doc lists "Hide until next
  session" in the menu and the update-detection and installer tests.
- README: new picture of a whole Mac desktop showing where the icon sits and how its card looks.

## [0.1.7] - 2026-11-14

- After an update, the running icon switches to the new version by itself within a second or
  two, for every install method (before, an icon started by a session start kept the old
  version until closed).
- README: new Update section with a table per install method.
- Fix: upgrading with the install script while the icon was running could leave an app that
  macOS kills as soon as it starts (exit code 137). The installer now replaces files by moving a
  fresh copy into place.

## [0.1.6] - 2026-11-14

- New "Hide until next session" menu item: the icon comes back with your next Claude Code
  session. "Quit" now keeps it closed, even for new sessions, until your next login.
- Every install method now brings a hidden or crashed icon back when a Claude Code session
  starts (before, only the plugin did).
- New `/attention-buddy:start` command for plugin installs; any manual start ends a Quit.
- `doctor` says when the icon is closed because you chose Quit.
- README: "Starting the icon again" is now "Closing and starting the icon", with the same method
  names as the Install table.

## [0.1.5] - 2026-11-14

- The card shows a session's current name from Claude Desktop: a rename appears within about
  half a second while the card is open, instead of after your next message in that session.
- README: Install and Uninstall are now matching tables, one row per install method.
- Documentation: "seen" also covers opening the card with a click; the design doc lists the
  card-dot tests and calls the card the session card everywhere.

## [0.1.4] - 2026-11-14

- Clicking the icon now opens the session card (as hovering does) and keeps it open until you
  choose something or click elsewhere.
- Click a session in the card to open exactly that session in the Claude desktop app. Terminal
  sessions are listed as "in a terminal" and can't be opened from the card.
- The card stays open while you move the pointer from the icon onto it.
- In the card, dots of sessions that need you blink red and working dots breathe slowly.
- New installs start at 2× the previous icon size (the slider still runs from 1× to 4×; a size
  you already chose is kept).

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

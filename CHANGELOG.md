# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org).

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

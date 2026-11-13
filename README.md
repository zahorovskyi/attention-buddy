<p align="center">
  <img src="docs/assets/icon.svg" width="96" alt="Attention Buddy">
</p>

<h1 align="center">Attention Buddy</h1>

<p align="center">
  <b>A tiny floating Claude Code buddy that jumps and waves when a session needs you.</b>
</p>

<p align="center">
  <a href="https://github.com/zahorovskyi/attention-buddy/actions/workflows/ci.yml"><img src="https://github.com/zahorovskyi/attention-buddy/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="docs/DESIGN.md">Design</a> ·
  <a href="#for-ai-agents">For AI agents</a>
</p>

<p align="center">
  <img src="docs/assets/states.svg" width="700" alt="Working, needs you, done, seen and error states">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hover-card-dark.svg">
    <img src="docs/assets/hover-card-light.svg" width="700" alt="Hovering over the icon shows every session: two need you, one is done, one is working">
  </picture>
  <br>
  <sub>Hover over the icon to see every session and what it needs.</sub>
</p>

## Why

Claude Code sessions run in the background while you do something else. When one stops to ask for
approval or a question, it just waits, and banners disappear while sounds get muted.

Attention Buddy is a small always-on-top mascot you drag anywhere on your screen. It stays calm
while Claude works and starts blinking red and waving the moment any session needs you.

- **Visual, silent, always there.** No sounds and no banners that vanish.
- **Every session at once.** One icon watches all your Claude Code sessions, in the desktop app
  and in the terminal.
- **Tiny and native.** One small Swift app, no web runtime, near-zero CPU.
- **Private.** No network access. It never reads your prompts, code or tool output.

## What it shows

| State | Looks like | When |
| --- | --- | --- |
| **Working** | dim clay color, legs stepping | Claude is working |
| **Needs you** | red, blinking, jumps and waves every 15 s | a session asks for approval, asks a question, or an MCP server needs input |
| **Seen** | steady red | you looked at Claude but have not answered yet; goes back to blinking after 3 minutes |
| **Done** | green, one happy hop | a session finished its turn |
| **Error** | red, shakes its head | a turn failed, for example on an API error |

With several sessions, the icon shows the most urgent one: needs you, error, seen, done, working.

## How it works

```mermaid
flowchart LR
    CC["Claude Code<br/>(desktop app or terminal)"] -- "hook events" --> H["attention-buddy-hook.sh"]
    H -- "one small JSON file<br/>per session" --> S[("~/.claude/attention-buddy/")]
    S -- "watched for changes" --> I["Floating icon"]
```

1. Claude Code runs a tiny hook script on a few events: a permission request, a tool finishing,
   the end of a turn, and so on.
2. The script writes the session's state to `~/.claude/attention-buddy/<session>.json`.
3. The icon reads those files and shows the most urgent state. Sessions whose process has exited
   are cleaned up automatically.

The full design, including every event and decision, is in [docs/DESIGN.md](docs/DESIGN.md).

## Install

**Requirements:** macOS 13 or later, the Xcode Command Line Tools (`xcode-select --install`) and
`jq` (included in macOS 15 and later; otherwise `brew install jq`). Attention Buddy builds from
source on your Mac, so there is no unsigned download to approve.

Pick **one** method.

<details open>
<summary><b>Claude Code plugin</b>: no terminal needed</summary>

In Claude Code, run:

```
/plugin marketplace add zahorovskyi/attention-buddy
/plugin install attention-buddy@attention-buddy
```

The plugin brings its own hooks. On your next session start it builds the icon in the background
(about 10 seconds) and starts it. The icon starts with each Claude Code session.

</details>

<details>
<summary><b>One-line install</b>: starts at login</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/zahorovskyi/attention-buddy/main/install.sh | sh
```

This downloads the latest release, builds it, installs `~/.local/bin/attention-buddy`, adds the
hooks to `~/.claude/settings.json` (after making a backup) and starts the icon at login.
Prefer to read it first? Download [install.sh](install.sh), read it, then run `sh install.sh`.
Add `--dry-run` to see what it would change.

</details>

<details>
<summary><b>From a clone</b></summary>

```bash
git clone https://github.com/zahorovskyi/attention-buddy.git
cd attention-buddy
./install.sh
```

Same result as the one-line install, built from your clone.

</details>

<details>
<summary><b>Homebrew</b></summary>

```bash
brew install zahorovskyi/tap/attention-buddy
attention-buddy setup
brew services start attention-buddy
```

`setup` adds the hooks to `~/.claude/settings.json` (with a backup). `brew services` starts the
icon now and at every login.

</details>

Check that everything is connected:

```bash
attention-buddy doctor
```

## Using it

- **Drag** the icon anywhere. It remembers the spot, even across restarts and display changes.
- **Click** it to jump to Claude. When something is waiting, it opens Claude's "Sessions waiting
  for you" list in the desktop app.
- **Right-click** it for "Show waiting sessions", "Mark all as seen", "Forget all sessions",
  "Settings…", "About Attention Buddy" (opens this page) and "Quit".
- It starts near the **bottom-right corner** of your screen, just above the Dock.
- **Hover** to see a card with every session and what it needs.
- **Resize** it in Settings…: a slider from the original size (1×) up to four times bigger (4×).
  The icon changes live as you drag. It grows away from its nearest screen corner, so it stays in
  place, and it keeps its size.

Advanced settings, from a terminal:

| Setting | Default | Example |
| --- | --- | --- |
| Seconds until "seen" asks again | 180 | `defaults write io.github.zahorovskyi.attention-buddy seenTimeout -float 300` |
| Seconds between waves | 15 | `defaults write io.github.zahorovskyi.attention-buddy repeatInterval -float 30` |

Restart the icon after changing these (right-click, Quit, then start it again). With
**Reduce Motion** turned on in macOS, it keeps the colors and the blink but skips the animations.

## What it changes on your Mac

| What | Plugin | Install script | Homebrew |
| --- | --- | --- | --- |
| The app | built into Claude Code's plugin data folder | `~/.local/bin/attention-buddy` | Homebrew prefix |
| Hooks | inside the plugin | added to `~/.claude/settings.json`, with a backup | added by `attention-buddy setup`, with a backup |
| Start at login | no; starts with Claude Code | `~/Library/LaunchAgents/io.github.zahorovskyi.attention-buddy.plist` | `brew services` |
| Session state | `~/.claude/attention-buddy/` | same | same |

Nothing else. No network access, no telemetry, no accounts.

## Uninstall

| Installed with | Remove with |
| --- | --- |
| Plugin | `/plugin uninstall attention-buddy`, then right-click the icon and choose Quit |
| Install script | `sh ~/.local/share/attention-buddy/install.sh --uninstall` |
| Homebrew | `attention-buddy setup --remove`, `brew services stop attention-buddy`, `brew uninstall attention-buddy` |

## Troubleshooting

Run `attention-buddy doctor` first. It checks the hooks, `jq`, the state folder and whether the
icon is running.

- **The icon never changes.** The hooks are not connected or not allowed. Organizations can
  restrict hooks with managed settings (`allowManagedHooksOnly`, `disableAllHooks`); `doctor`
  reports this.
- **Installed twice** (plugin and script). It still works, but remove one; `doctor` tells you which.
- **The icon is off screen.** It moves back by itself when displays change. You can also reset
  its spot: `defaults delete io.github.zahorovskyi.attention-buddy positionX`.

## For AI agents

Point your coding agent at this repository and ask, for example:

> Read https://github.com/zahorovskyi/attention-buddy and help me install it.

Agents will find:

- [AGENTS.md](AGENTS.md): what the app does, which install method to pick, exact commands, how to
  verify and uninstall, and how to work on the code.
- [llms.txt](llms.txt): a short index with direct links to every document.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing and the release process.

## License

[MIT](LICENSE) © zahorovskyi.

Attention Buddy is an independent project. It is not affiliated with, endorsed by or sponsored by
Anthropic. "Claude" and the Claude Code mascot artwork belong to Anthropic and are not covered by
the MIT license; see [NOTICE](NOTICE).

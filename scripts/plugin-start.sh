#!/bin/sh
# plugin-start.sh: run by the Claude Code plugin on every session start.
#
# Builds the icon once per plugin version into the plugin's persistent data folder
# ($CLAUDE_PLUGIN_DATA), then starts it in the background. Returns immediately.
# A single-instance lock inside the app means extra starts simply exit.
#
# Claude Code adds SessionStart output to Claude's context, so this script prints nothing,
# except one short note the first time the Command Line Tools are missing, so Claude can
# tell the user.

root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
data=${CLAUDE_PLUGIN_DATA:-"$HOME/.claude/plugins/data/attention-buddy"}
binary="$data/bin/attention-buddy"
built_from="$data/built-from"
log="$data/plugin.log"
failure_noted="$data/build-failure-noted"

mkdir -p "$data/bin" 2>/dev/null || exit 0

start_icon() {
  nohup "$binary" >>"$log" 2>&1 &
}

# Runs detached (see below): build, swap the binary in, start the icon.
if [ "${1:-}" = --build-and-start ]; then
  if sh "$root/scripts/build.sh" --output "$binary.new" >>"$log" 2>&1; then
    mv -f "$binary.new" "$binary"
    printf '%s\n' "$root" >"$built_from"
    start_icon
  else
    rm -f "$binary.new"
  fi
  exit 0
fi

# Already built for this plugin version: just start it.
if [ -x "$binary" ] && [ "$(cat "$built_from" 2>/dev/null)" = "$root" ]; then
  start_icon
  exit 0
fi

if ! command -v swiftc >/dev/null 2>&1; then
  if [ ! -f "$failure_noted" ]; then
    : >"$failure_noted"
    echo "Attention Buddy (plugin) could not build its floating icon because the Xcode Command Line Tools are missing. Tell the user to run: xcode-select --install"
  fi
  exit 0
fi

# First run or a new plugin version: build detached, about 10 seconds, so the session never waits.
nohup sh "$0" --build-and-start >/dev/null 2>&1 &
exit 0

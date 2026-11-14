#!/bin/sh
# plugin-start.sh: starts the floating icon for Claude Code plugin installs.
#
#   plugin-start.sh            run by the plugin on every session start
#   plugin-start.sh --manual   run by the /attention-buddy:start command
#
# Builds the icon once per plugin version into the plugin's persistent data folder
# ($CLAUDE_PLUGIN_DATA), then starts it in the background. Returns immediately. A
# single-instance lock inside the app means extra starts simply exit.
#
# On session start it leaves the icon closed if the user chose Quit since the Mac last started
# (the `.quit` note); --manual starts it anyway, which also ends the Quit.
#
# Claude Code adds SessionStart output to Claude's context, so on session start this script
# prints nothing, except one short note the first time the Command Line Tools are missing.
# With --manual it prints one line saying what happened.

root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
data=${CLAUDE_PLUGIN_DATA:-"$HOME/.claude/plugins/data/attention-buddy"}
state_dir=${ATTENTION_BUDDY_DIR:-"$HOME/.claude/attention-buddy"}
binary="$data/bin/attention-buddy"
built_from="$data/built-from"
log="$data/plugin.log"
failure_noted="$data/build-failure-noted"
mode=${1:-session}

mkdir -p "$data/bin" 2>/dev/null || exit 0

say() {
  if [ "$mode" = --manual ]; then
    printf '%s\n' "$*"
  fi
}

# True while a Quit counts: the note is newer than the last Mac start.
quit_note_active() {
  note="$state_dir/.quit"
  [ -f "$note" ] || return 1
  quit_at=$(tr -dc '0-9' <"$note")
  [ -n "$quit_at" ] || return 1
  boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
  [ -n "$boot" ] || return 0
  [ "$quit_at" -ge "$boot" ]
}

start_icon() {
  nohup "$binary" >>"$log" 2>&1 &
}

# Runs detached (see below): build, swap the binary in, start the icon.
if [ "$mode" = --build-and-start ]; then
  if sh "$root/scripts/build.sh" --output "$binary.new" >>"$log" 2>&1; then
    mv -f "$binary.new" "$binary"
    printf '%s\n' "$root" >"$built_from"
    start_icon
  else
    rm -f "$binary.new"
  fi
  exit 0
fi

if [ "$mode" = session ] && quit_note_active; then
  exit 0
fi
if [ "$mode" = --manual ]; then
  rm -f "$state_dir/.quit"
fi

# Already built for this plugin version: just start it.
if [ -x "$binary" ] && [ "$(cat "$built_from" 2>/dev/null)" = "$root" ]; then
  start_icon
  say "Attention Buddy is starting; the icon appears in a moment."
  exit 0
fi

if ! command -v swiftc >/dev/null 2>&1; then
  if [ "$mode" = --manual ]; then
    say "Attention Buddy can't build its icon because the Xcode Command Line Tools are missing. Run: xcode-select --install"
  elif [ ! -f "$failure_noted" ]; then
    : >"$failure_noted"
    echo "Attention Buddy (plugin) could not build its floating icon because the Xcode Command Line Tools are missing. Tell the user to run: xcode-select --install"
  fi
  exit 0
fi

# First run or a new plugin version: build detached, about 10 seconds, so nothing waits.
nohup sh "$0" --build-and-start >/dev/null 2>&1 &
say "Attention Buddy is building its icon (about 10 seconds); it appears when ready."
exit 0

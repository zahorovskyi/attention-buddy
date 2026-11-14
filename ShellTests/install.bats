#!/usr/bin/env bats
# Tests for install.sh and scripts/plugin-start.sh, in a throwaway home folder.
# launchctl is replaced by a stub that only records its arguments; the real build is
# covered separately by scripts/build.sh in CI.

ROOT="$BATS_TEST_DIRNAME/.."
INSTALL="$ROOT/install.sh"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR ATTENTION_BUDDY_DIR ATTENTION_BUDDY_REF
  export SETTINGS="$HOME/.claude/settings.json"

  stubs="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$stubs"
  printf '#!/bin/sh\necho "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl.log" >"$stubs/launchctl"
  chmod +x "$stubs/launchctl"
  export PATH="$stubs:$PATH"

  fake_binary="$BATS_TEST_TMPDIR/fake-attention-buddy"
  printf '#!/bin/sh\necho "fake attention-buddy $*"\n' >"$fake_binary"
  chmod +x "$fake_binary"
  export ATTENTION_BUDDY_BINARY="$fake_binary"
}

our_hook_count() {
  jq '[.hooks[]?[]?.hooks[]? | select(.command | contains("attention-buddy-hook"))] | length' "$SETTINGS"
}

@test "a full install puts the binary, the hook script, the hooks and the login item in place" {
  run sh "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/attention-buddy" ]
  [ -x "$HOME/.local/share/attention-buddy/attention-buddy-hook.sh" ]
  [ -x "$HOME/.local/share/attention-buddy/install.sh" ]
  [ "$(our_hook_count)" -eq 11 ]
  plist="$HOME/Library/LaunchAgents/io.github.zahorovskyi.attention-buddy.plist"
  plutil -lint "$plist"
  grep -q "$HOME/.local/bin/attention-buddy" "$plist"
  grep -q "bootstrap gui/$(id -u) $plist" "$BATS_TEST_TMPDIR/launchctl.log"
}

@test "the installed hook command actually runs" {
  sh "$INSTALL" --no-login-item
  command=$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")
  printf '{"hook_event_name":"Stop","session_id":"s1"}' | sh -c "$command"
  [ "$(jq -r .status "$HOME/.claude/attention-buddy/s1.json")" = done ]
}

@test "existing settings and hooks are kept, and a backup is made" {
  mkdir -p "$HOME/.claude"
  printf '%s' '{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other-tool"}]}]}}' >"$SETTINGS"
  run sh "$INSTALL" --no-login-item
  [ "$status" -eq 0 ]
  [ "$(jq -r .model "$SETTINGS")" = x ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = other-tool ]
  [ "$(jq '.hooks.Stop | length' "$SETTINGS")" -eq 2 ]
  ls "$HOME/.claude/"settings.json.attention-buddy-*.bak
}

@test "installing twice leaves exactly one hook per event" {
  sh "$INSTALL" --no-login-item
  sh "$INSTALL" --no-login-item
  [ "$(our_hook_count)" -eq 11 ]
}

@test "removing hooks keeps everything else" {
  mkdir -p "$HOME/.claude"
  printf '%s' '{"hooks":{"Stop":[{"hooks":[{"command":"other-tool"}]}],"Notification":[]}}' >"$SETTINGS"
  sh "$INSTALL" --no-login-item
  run sh "$INSTALL" --remove-hooks
  [ "$status" -eq 0 ]
  [ "$(our_hook_count)" -eq 0 ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" = other-tool ]
  [ "$(jq '.hooks | has("Notification")' "$SETTINGS")" = true ]
  [ "$(jq '.hooks | has("PostToolUse")' "$SETTINGS")" = false ]
}

@test "broken settings.json stops the installer without changing it" {
  mkdir -p "$HOME/.claude"
  printf '{"hooks": [broken' >"$SETTINGS"
  run sh "$INSTALL" --no-login-item
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
  [ "$(cat "$SETTINGS")" = '{"hooks": [broken' ]
}

@test "with the plugin installed the hooks are skipped unless forced" {
  mkdir -p "$HOME/.claude/plugins"
  printf '%s' '{"version":2,"plugins":{"attention-buddy@attention-buddy":[{}]}}' \
    >"$HOME/.claude/plugins/installed_plugins.json"
  run sh "$INSTALL" --no-login-item
  [ "$status" -eq 0 ]
  [[ "$output" == *"plugin is installed"* ]]
  [ ! -f "$SETTINGS" ]
  sh "$INSTALL" --no-login-item --force
  [ "$(our_hook_count)" -eq 11 ]
}

@test "a dry run changes nothing" {
  run sh "$INSTALL" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would"* ]]
  [ ! -e "$HOME/.local" ]
  [ ! -e "$SETTINGS" ]
  [ ! -e "$HOME/Library" ]
}

@test "uninstall removes everything it added" {
  sh "$INSTALL"
  mkdir -p "$HOME/.claude/attention-buddy" && touch "$HOME/.claude/attention-buddy/s1.json"
  run sh "$INSTALL" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/attention-buddy" ]
  [ ! -e "$HOME/.local/share/attention-buddy" ]
  [ ! -e "$HOME/.claude/attention-buddy" ]
  [ ! -e "$HOME/Library/LaunchAgents/io.github.zahorovskyi.attention-buddy.plist" ]
  [ "$(our_hook_count)" -eq 0 ]
  grep -q "bootout gui/$(id -u)/io.github.zahorovskyi.attention-buddy" "$BATS_TEST_TMPDIR/launchctl.log"
}

@test "hooks-only mode points Homebrew installs at the stable opt folder" {
  cellar="$BATS_TEST_TMPDIR/brew/Cellar/attention-buddy/0.1.0"
  mkdir -p "$cellar/share/attention-buddy"
  cp "$ROOT/hooks/attention-buddy-hook.sh" "$cellar/share/attention-buddy/"
  run sh "$INSTALL" --hooks-only --prefix "$cellar"
  [ "$status" -eq 0 ]
  command=$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")
  [ "$command" = "\"$BATS_TEST_TMPDIR/brew/opt/attention-buddy/share/attention-buddy/attention-buddy-hook.sh\"" ]
}

@test "a prefix with spaces still produces a working hook command" {
  prefix="$BATS_TEST_TMPDIR/my tools"
  sh "$INSTALL" --no-login-item --prefix "$prefix"
  command=$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")
  printf '{"hook_event_name":"Stop","session_id":"s2"}' | sh -c "$command"
  [ -f "$HOME/.claude/attention-buddy/s2.json" ]
}

@test "CLAUDE_CONFIG_DIR is respected" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/other-config"
  sh "$INSTALL" --no-login-item
  [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
  [ ! -e "$SETTINGS" ]
}

@test "unknown options are rejected with a hint" {
  run sh "$INSTALL" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"--help"* ]]
}

@test "plugin: the session-start script returns at once, prints nothing and starts the icon" {
  data="$BATS_TEST_TMPDIR/plugin-data"
  mkdir -p "$data/bin"
  cp "$ATTENTION_BUDDY_BINARY" "$data/bin/attention-buddy"
  printf '%s\n' "$ROOT" >"$data/built-from"
  run env CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$data" sh "$ROOT/scripts/plugin-start.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  sleep 1
  grep -q "fake attention-buddy" "$data/plugin.log"
}

@test "plugin: the hook config references only files that exist" {
  jq -e . "$ROOT/hooks/hooks.json" >/dev/null
  jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json" | sort -u | while read -r command; do
    path=$(printf '%s' "$command" | tr -d '"' | sed "s#\${CLAUDE_PLUGIN_ROOT}#$ROOT#")
    [ -x "$path" ]
  done
}

@test "plugin: every hook event the installer adds is also in the plugin" {
  installer_events=$(sed -n 's/^hook_events="\(.*\)"$/\1/p' "$INSTALL" | tr ' ' '\n' | sort)
  plugin_events=$(jq -r '.hooks | keys[]' "$ROOT/hooks/hooks.json" | sort)
  [ "$installer_events" = "$plugin_events" ]
}

plugin_setup() {
  data="$BATS_TEST_TMPDIR/plugin-data"
  export ATTENTION_BUDDY_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$data/bin" "$ATTENTION_BUDDY_DIR"
  cp "$ATTENTION_BUDDY_BINARY" "$data/bin/attention-buddy"
  printf '%s\n' "$ROOT" >"$data/built-from"
}

@test "plugin: after Quit, a session start leaves the icon closed" {
  plugin_setup
  date +%s >"$ATTENTION_BUDDY_DIR/.quit"
  run env CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$data" sh "$ROOT/scripts/plugin-start.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  sleep 1
  [ ! -s "$data/plugin.log" ]
}

@test "plugin: /attention-buddy:start ends a Quit, starts the icon and says so" {
  plugin_setup
  date +%s >"$ATTENTION_BUDDY_DIR/.quit"
  run env CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$data" sh "$ROOT/scripts/plugin-start.sh" --manual
  [ "$status" -eq 0 ]
  [[ "$output" == *"Attention Buddy is starting"* ]]
  [ ! -e "$ATTENTION_BUDDY_DIR/.quit" ]
  sleep 1
  grep -q "fake attention-buddy" "$data/plugin.log"
}

@test "plugin: the start command is a user-only skill that runs the start script" {
  skill="$ROOT/skills/start/SKILL.md"
  [ -f "$skill" ]
  grep -q '^name: start$' "$skill"
  grep -q '^disable-model-invocation: true$' "$skill"
  grep -q 'scripts/plugin-start.sh --manual' "$skill"
  [ -x "$ROOT/scripts/plugin-start.sh" ]
}

@test "reinstalling replaces the app with a new file, so a running copy can't break it" {
  sh "$INSTALL" --no-login-item
  before=$(ls -i "$HOME/.local/bin/attention-buddy" | awk '{print $1}')
  sh "$INSTALL" --no-login-item
  after=$(ls -i "$HOME/.local/bin/attention-buddy" | awk '{print $1}')
  [ "$before" != "$after" ]
  [ -z "$(ls "$HOME/.local/bin" | grep '\.new\.')" ]
  [ -x "$HOME/.local/bin/attention-buddy" ]
}

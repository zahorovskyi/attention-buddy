#!/bin/sh
# Attention Buddy installer.
#
#   curl -fsSL https://raw.githubusercontent.com/zahorovskyi/attention-buddy/main/install.sh | sh
#   ./install.sh                  install from a clone
#   ./install.sh --uninstall      remove everything this script added
#
# Options:
#   --prefix <dir>       Install the binary to <dir>/bin (default: ~/.local)
#   --hooks-only         Only add the Claude Code hooks (used by `attention-buddy setup`)
#   --remove-hooks       Only remove the Claude Code hooks
#   --no-login-item      Do not start the icon at login
#   --force              Add hooks even if the Claude Code plugin is installed
#   --dry-run            Show what would change, change nothing
#   -h, --help           Show this help
#
# Environment:
#   CLAUDE_CONFIG_DIR       Claude Code config folder (default: ~/.claude)
#   ATTENTION_BUDDY_DIR    State folder (default: ~/.claude/attention-buddy)
#   ATTENTION_BUDDY_REF    Git tag or branch to download when not run from a clone
#                           (default: the latest release)

# jq programs are single-quoted on purpose: their $variables belong to jq, not the shell.
# shellcheck disable=SC2016
set -eu

repository="zahorovskyi/attention-buddy"
label="io.github.zahorovskyi.attention-buddy"
hook_marker="attention-buddy-hook"
hook_events="SessionStart SessionEnd UserPromptSubmit PermissionRequest PermissionDenied PostToolUse PostToolUseFailure Elicitation ElicitationResult Stop StopFailure"

prefix="$HOME/.local"
mode=install
login_item=yes
force=no
dry_run=no

config_dir=${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}
settings="$config_dir/settings.json"
state_dir=${ATTENTION_BUDDY_DIR:-"$HOME/.claude/attention-buddy"}
launch_agent="$HOME/Library/LaunchAgents/$label.plist"

say() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,23p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true
}

while [ $# -gt 0 ]; do
  option=$1
  shift
  case $option in
    --prefix)
      [ $# -ge 1 ] || fail "--prefix needs a folder"
      prefix=$1
      shift
      ;;
    --hooks-only) mode=hooks ;;
    --remove-hooks) mode=remove-hooks ;;
    --uninstall) mode=uninstall ;;
    --no-login-item) login_item=no ;;
    --force) force=yes ;;
    --dry-run) dry_run=yes ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) fail "Unknown option: $option (see --help)" ;;
  esac
done

bin_path="$prefix/bin/attention-buddy"
share_dir="$prefix/share/attention-buddy"

find_jq() {
  for candidate in "$(command -v jq 2>/dev/null || true)" /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

jq=$(find_jq) || fail "jq is required. macOS 15 and later include it; otherwise run: brew install jq"

# --- Claude Code hooks -------------------------------------------------------------------

# The hook path written into settings.json. Homebrew's versioned Cellar folder is swapped for
# its stable "opt" link, so the hooks keep working after `brew upgrade`.
hook_command_path() {
  path="$share_dir/attention-buddy-hook.sh"
  case $path in
    */Cellar/attention-buddy/*)
      path="${path%%/Cellar/*}/opt/attention-buddy/share/attention-buddy/attention-buddy-hook.sh"
      ;;
  esac
  printf '%s' "$path"
}

plugin_installed() {
  registry="$config_dir/plugins/installed_plugins.json"
  [ -f "$registry" ] && grep -q '"attention-buddy@' "$registry"
}

# Rewrites settings.json: removes every hook of ours, then (when $1 is "add") adds one per event.
# Other hooks and settings are left exactly as they were.
update_settings() {
  action=$1
  if [ "$action" = add ] && plugin_installed && [ "$force" = no ]; then
    warn "the Claude Code plugin is installed and already provides the hooks; skipping settings.json (use --force to add them anyway)"
    return 0
  fi
  if [ ! -f "$settings" ]; then
    if [ "$action" = remove ]; then
      return 0
    fi
    current='{}'
  else
    current=$(cat "$settings")
    printf '%s' "$current" | "$jq" -e 'type == "object"' >/dev/null 2>&1 ||
      fail "$settings is not valid JSON; fix it first. Nothing was changed."
  fi

  command_value="\"$(hook_command_path)\""
  updated=$(printf '%s' "$current" | "$jq" \
    --arg marker "$hook_marker" --arg command "$command_value" --arg action "$action" \
    --arg events "$hook_events" '
    def ours: any(.hooks[]?; ((.command? // "") | tostring | contains($marker)));
    def strip:
      if (.hooks | type) == "object" then
        .hooks |= with_entries(
          .value as $original
          | .value |= (if type == "array" then map(select(ours | not)) else . end)
          | select(($original | type) != "array" or ($original | length) == 0 or (.value | length) > 0))
      else . end;
    strip
    | if $action == "add" then
        reduce ($events | split(" ")[]) as $event (.;
          .hooks[$event] = ((.hooks[$event] // []) + [{hooks: [{type: "command", command: $command, timeout: 10}]}]))
      else . end
    | if .hooks == {} then del(.hooks) else . end') || fail "could not update $settings"

  if [ "$updated" = "$current" ]; then
    return 0
  fi
  if [ "$dry_run" = yes ]; then
    if [ "$action" = add ]; then
      say "Would add Claude Code hooks to $settings"
    else
      say "Would remove Claude Code hooks from $settings"
    fi
    return 0
  fi
  mkdir -p "$config_dir"
  if [ -f "$settings" ]; then
    backup="$settings.attention-buddy-$(date +%Y%m%d-%H%M%S).bak"
    cp "$settings" "$backup"
    say "Backed up settings to $backup"
  fi
  temporary="$settings.tmp.$$"
  printf '%s\n' "$updated" >"$temporary"
  mv -f "$temporary" "$settings"
  if [ "$action" = add ]; then
    say "Connected Claude Code: added hooks to $settings"
  else
    say "Removed Claude Code hooks from $settings"
  fi
}

# --- Login item --------------------------------------------------------------------------

write_launch_agent() {
  if [ "$dry_run" = yes ]; then
    say "Would start the icon at login ($launch_agent)"
    return 0
  fi
  mkdir -p "$(dirname "$launch_agent")"
  cat >"$launch_agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin_path</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$launch_agent" || warn "could not start the login item; run $bin_path to start the icon"
  say "The icon starts now and at every login"
}

remove_launch_agent() {
  if [ ! -f "$launch_agent" ]; then
    return 0
  fi
  if [ "$dry_run" = yes ]; then
    say "Would remove the login item ($launch_agent)"
    return 0
  fi
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  rm -f "$launch_agent"
  say "Removed the login item"
}

# --- Source and build --------------------------------------------------------------------

# A clone has scripts/build.sh next to this file. Otherwise (curl | sh) download the source.
find_source() {
  script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
  if [ -n "$script_dir" ] && [ -f "$script_dir/scripts/build.sh" ] && [ -d "$script_dir/Sources" ]; then
    printf '%s' "$script_dir"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || fail "curl is required to download the source"
  ref=${ATTENTION_BUDDY_REF:-}
  if [ -z "$ref" ]; then
    ref=$(curl -fsSL "https://api.github.com/repos/$repository/releases/latest" 2>/dev/null |
      "$jq" -r '.tag_name // empty' 2>/dev/null || true)
  fi
  if [ -z "$ref" ]; then
    ref=main
  fi
  download_dir=$(mktemp -d)
  say "Downloading $repository ($ref)" >&2
  curl -fsSL "https://github.com/$repository/archive/$ref.tar.gz" | tar -xz -C "$download_dir" ||
    fail "could not download https://github.com/$repository/archive/$ref.tar.gz"
  for folder in "$download_dir"/*; do
    printf '%s' "$folder"
    return 0
  done
  fail "the download was empty"
}

# Copies to a temporary file next to the target, then moves it into place. Overwriting a binary
# in place while the icon runs makes macOS kill the next start of it (the kernel keeps the old
# code signature for that file), and a hook script may be running while it is replaced. A move
# gives a new file instead.
replace_file() {
  temporary="$2.new.$$"
  cp "$1" "$temporary"
  chmod 755 "$temporary"
  mv -f "$temporary" "$2"
}

install_files() {
  source_dir=$(find_source)
  if [ -n "${ATTENTION_BUDDY_BINARY:-}" ]; then
    # Advanced and for tests: use an already built binary instead of building.
    built=$ATTENTION_BUDDY_BINARY
  else
    command -v swiftc >/dev/null 2>&1 ||
      fail "swiftc was not found. Install the Xcode Command Line Tools first: xcode-select --install"
    built="$source_dir/build/attention-buddy"
    if [ "$dry_run" = yes ]; then
      say "Would build attention-buddy from $source_dir"
    else
      say "Building (about 10 seconds)"
      sh "$source_dir/scripts/build.sh" --output "$built" >/dev/null
    fi
  fi
  if [ "$dry_run" = yes ]; then
    say "Would install $bin_path and $share_dir"
    return 0
  fi
  mkdir -p "$prefix/bin" "$share_dir"
  replace_file "$built" "$bin_path"
  replace_file "$source_dir/hooks/attention-buddy-hook.sh" "$share_dir/attention-buddy-hook.sh"
  replace_file "$source_dir/install.sh" "$share_dir/install.sh"
  say "Installed $bin_path"
}

# --- Modes -------------------------------------------------------------------------------

case $mode in
  hooks)
    [ -f "$share_dir/attention-buddy-hook.sh" ] || fail "hook script not found in $share_dir"
    update_settings add
    ;;
  remove-hooks)
    update_settings remove
    ;;
  install)
    [ "$(uname -s)" = Darwin ] || fail "Attention Buddy runs on macOS only"
    install_files
    update_settings add
    if [ "$login_item" = yes ]; then
      write_launch_agent
    fi
    if [ "$dry_run" = no ]; then
      case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) say "Tip: add $prefix/bin to your PATH to run attention-buddy from a terminal" ;;
      esac
      say "Done. Check the setup any time with: $bin_path doctor"
    fi
    ;;
  uninstall)
    remove_launch_agent
    update_settings remove
    if [ "$dry_run" = yes ]; then
      say "Would delete $bin_path, $share_dir and $state_dir"
    else
      rm -f "$bin_path"
      rm -rf "$share_dir" "$state_dir"
      defaults delete "$label" >/dev/null 2>&1 || true
      say "Attention Buddy is uninstalled"
    fi
    ;;
esac

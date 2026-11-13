#!/bin/sh
# attention-buddy-hook.sh: records each Claude Code session's attention state for the floating icon.
#
# Claude Code runs this on a few hook events and passes the event as JSON on stdin.
# It writes one small JSON file per session into the state folder
# ($ATTENTION_BUDDY_DIR, default ~/.claude/attention-buddy).
#
# Safety rules:
# - It never prints anything and always exits 0, so it cannot block or change Claude Code.
# - It keeps only the event name, session id, tool name, working folder and session title.
#   Prompts, code and tool output are never stored.
# - Updates for one session are serialized with a lock folder and written atomically.

# jq programs are single-quoted on purpose: their $variables belong to jq, not the shell.
# shellcheck disable=SC2016

state_dir=${ATTENTION_BUDDY_DIR:-"$HOME/.claude/attention-buddy"}
separator=$(printf '\037')

# Finds jq even when Claude Code was started with a minimal PATH.
# ATTENTION_BUDDY_JQ overrides the search (used by the tests).
find_jq() {
  if [ -n "${ATTENTION_BUDDY_JQ+set}" ]; then
    if [ -x "$ATTENTION_BUDDY_JQ" ]; then
      printf '%s' "$ATTENTION_BUDDY_JQ"
      return 0
    fi
    return 1
  fi
  for candidate in "$(command -v jq 2>/dev/null)" /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# The Claude Code process that owns this session. If a shell sits in between (for example
# when a plugin hook command is wrapped in "sh -c"), skip it.
owner_pid() {
  pid=$PPID
  name=$(ps -o comm= -p "$pid" 2>/dev/null)
  case ${name##*/} in
    sh | bash | zsh | dash | -sh | -bash | -zsh)
      parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$parent" ]; then
        pid=$parent
      fi
      ;;
  esac
  printf '%s' "$pid"
}

# A short fingerprint of the tool call, used to match a permission request with its result.
#
# Questions (AskUserQuestion) match by tool name only: Claude Code adds the user's answers to the
# tool input after answering, and only one question can be open at a time.
tool_key() {
  printf '%s' "$payload" |
    "$jq" -cS '[.tool_name, (if .tool_name == "AskUserQuestion" then null else .tool_input end)]' |
    shasum -a 256 | cut -c1-16
}

acquire_lock() {
  attempts=0
  until mkdir "$lock" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      # Two seconds without the lock: its owner most likely died. Take it over.
      rm -rf "$lock"
      mkdir "$lock" 2>/dev/null || return 1
      break
    fi
    sleep 0.02
  done
  trap 'rmdir "$lock" 2>/dev/null' EXIT
}

write_state() {
  now=$(date +%s)
  temporary="$file.tmp.$$"
  "$jq" -n \
    --arg session "$session" --arg status "$status" --arg reason "$reason" --arg tool "$state_tool" \
    --arg cwd "$cwd" --arg title "$title" --arg key "$key" --arg pid "$(owner_pid)" \
    --arg stamp "$now-$$" --arg now "$now" \
    '{version: 1, session_id: $session, status: $status, reason: $reason, tool: $tool, cwd: $cwd,
      title: $title, pending_key: $key, pid: ($pid | tonumber? // 0), stamp: $stamp,
      updated_at: ($now | tonumber)}' >"$temporary" &&
    mv -f "$temporary" "$file"
  rm -f "$temporary"
}

main() {
  jq=$(find_jq) || return 0
  payload=$(cat) || return 0

  fields=$(printf '%s' "$payload" | "$jq" -r --arg sep "$separator" '
    [.hook_event_name, .session_id, .tool_name, .cwd, .session_title]
    | map(. // "" | tostring | gsub("[[:cntrl:]]"; " "))
    | join($sep)') || return 0
  IFS=$separator read -r event session tool cwd title <<EOF
$fields
EOF

  # Session ids become file names: allow only safe characters.
  case $session in
    '' | *[!A-Za-z0-9_-]*) return 0 ;;
  esac
  if [ "${#session}" -gt 128 ]; then
    return 0
  fi

  file="$state_dir/$session.json"
  lock="$state_dir/.$session.lock"
  status=''
  reason=''
  key=''
  state_tool=''

  case $event in
    SessionEnd)
      rm -f "$file"
      return 0
      ;;
    SessionStart) status=idle ;;
    UserPromptSubmit | ElicitationResult) status=working ;;
    PostToolUse | PostToolUseFailure | PermissionDenied) status=working ;;
    PermissionRequest)
      status=needs
      reason=approval
      if [ "$tool" = AskUserQuestion ]; then
        reason=question
      fi
      state_tool=$tool
      key=$(tool_key)
      ;;
    Elicitation)
      status=needs
      reason=input
      ;;
    Stop) status='done' ;;
    StopFailure) status=error ;;
    *) return 0 ;;
  esac

  mkdir -p "$state_dir" || return 0
  acquire_lock || return 0

  current_status=''
  current_key=''
  current_title=''
  if [ -f "$file" ]; then
    current=$("$jq" -r --arg sep "$separator" \
      '[.status, .pending_key, .title] | map(. // "" | tostring) | join($sep)' "$file" 2>/dev/null)
    IFS=$separator read -r current_status current_key current_title <<EOF
$current
EOF
  fi

  # SessionStart also fires on resume, /clear and compaction: never reset a known session.
  if [ "$event" = SessionStart ] && [ -n "$current_status" ]; then
    return 0
  fi

  case $event in
    PostToolUse | PostToolUseFailure | PermissionDenied)
      # A different tool finishing must not clear a pending approval.
      if [ "$current_status" = needs ] && [ -n "$current_key" ] && [ "$(tool_key)" != "$current_key" ]; then
        return 0
      fi
      # Already working and nothing new to record: skip the write.
      if [ "$current_status" = working ] && { [ -z "$title" ] || [ "$title" = "$current_title" ]; }; then
        return 0
      fi
      ;;
  esac

  if [ -z "$title" ]; then
    title=$current_title
  fi
  write_state
}

main >/dev/null 2>&1
exit 0

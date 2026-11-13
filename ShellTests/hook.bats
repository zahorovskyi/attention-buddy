#!/usr/bin/env bats
# Tests for hooks/attention-buddy-hook.sh. Run with: bats ShellTests

HOOK="$BATS_TEST_DIRNAME/../hooks/attention-buddy-hook.sh"

setup() {
  export ATTENTION_BUDDY_DIR="$BATS_TEST_TMPDIR/state"
}

# send <json>: runs the hook with the event on stdin and captures its output.
send() {
  run sh -c 'printf "%s" "$1" | "$2"' _ "$1" "$HOOK"
}

event() {
  printf '{"hook_event_name":"%s","session_id":"%s"%s}' "$1" "${2:-s1}" "${3:-}"
}

state() {
  jq -r ".$1" "$ATTENTION_BUDDY_DIR/${2:-s1}.json"
}

bash_tool=',"tool_name":"Bash","tool_input":{"command":"npm test"}'
read_tool=',"tool_name":"Read","tool_input":{"file_path":"/x"}'

@test "every event exits 0 and prints nothing" {
  for name in SessionStart UserPromptSubmit PermissionRequest PostToolUse PostToolUseFailure \
    PermissionDenied Elicitation ElicitationResult Stop StopFailure SessionEnd Unknown; do
    send "$(event "$name" s1 "$bash_tool")"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "SessionStart creates an idle session" {
  send "$(event SessionStart)"
  [ "$(state status)" = idle ]
}

@test "SessionStart on resume or compaction does not reset a known session" {
  send "$(event UserPromptSubmit)"
  send "$(event SessionStart s1 ',"source":"compact"')"
  [ "$(state status)" = working ]
}

@test "a prompt starts work and stores the session title" {
  send "$(event UserPromptSubmit s1 ',"session_title":"Fix the login page","cwd":"/work/app"')"
  [ "$(state status)" = working ]
  [ "$(state title)" = "Fix the login page" ]
  [ "$(state cwd)" = /work/app ]
}

@test "a permission request needs approval and names the tool" {
  send "$(event PermissionRequest s1 "$bash_tool")"
  [ "$(state status)" = needs ]
  [ "$(state reason)" = approval ]
  [ "$(state tool)" = Bash ]
  [ -n "$(state pending_key)" ]
}

@test "AskUserQuestion is a question, not an approval" {
  send "$(event PermissionRequest s1 ',"tool_name":"AskUserQuestion","tool_input":{"questions":[]}')"
  [ "$(state reason)" = question ]
}

@test "answering a question clears it even though the answers were added to the tool input" {
  send "$(event PermissionRequest s1 ',"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick"}]}')"
  send "$(event PostToolUse s1 ',"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick"}],"answers":{"Pick":"A"}}')"
  [ "$(state status)" = working ]
}

@test "another tool finishing does not clear a pending approval" {
  send "$(event PermissionRequest s1 "$bash_tool")"
  send "$(event PostToolUse s1 "$read_tool")"
  [ "$(state status)" = needs ]
}

@test "the approved tool finishing clears the approval" {
  send "$(event PermissionRequest s1 "$bash_tool")"
  send "$(event PostToolUse s1 "$bash_tool")"
  [ "$(state status)" = working ]
  [ "$(state reason)" = "" ]
}

@test "a failed or denied tool also clears the approval" {
  send "$(event PermissionRequest s1 "$bash_tool")"
  send "$(event PostToolUseFailure s1 "$bash_tool")"
  [ "$(state status)" = working ]
  send "$(event PermissionRequest s1 "$bash_tool")"
  send "$(event PermissionDenied s1 "$bash_tool")"
  [ "$(state status)" = working ]
}

@test "a new prompt clears any pending request" {
  send "$(event PermissionRequest s1 "$bash_tool")"
  send "$(event UserPromptSubmit)"
  [ "$(state status)" = working ]
}

@test "MCP input requests need the user until answered" {
  send "$(event Elicitation)"
  [ "$(state status)" = needs ]
  [ "$(state reason)" = input ]
  send "$(event ElicitationResult)"
  [ "$(state status)" = working ]
}

@test "end of turn is done, a failed turn is an error" {
  send "$(event Stop)"
  [ "$(state status)" = done ]
  send "$(event StopFailure)"
  [ "$(state status)" = error ]
}

@test "the title is kept across events" {
  send "$(event UserPromptSubmit s1 ',"session_title":"Release notes"')"
  send "$(event PermissionRequest s1 "$bash_tool")"
  send "$(event Stop)"
  [ "$(state title)" = "Release notes" ]
}

@test "SessionEnd deletes the session file" {
  send "$(event Stop)"
  send "$(event SessionEnd)"
  [ ! -e "$ATTENTION_BUDDY_DIR/s1.json" ]
}

@test "each write gets a new stamp" {
  send "$(event PermissionRequest s1 "$bash_tool")"
  first=$(state stamp)
  sleep 1
  send "$(event PermissionRequest s1 "$read_tool")"
  [ "$(state stamp)" != "$first" ]
}

@test "the recorded owner is a live process, skipping a wrapping shell" {
  # Called straight from this test's shell, like Claude Code calling the hook.
  printf '%s' "$(event Stop)" | "$HOOK"
  owner=$(state pid)
  [ "$owner" -gt 1 ]
  kill -0 "$owner"
}

@test "unsafe session ids never become file names" {
  for id in '../escape' 'a/b' 'with space' ''; do
    send "$(printf '{"hook_event_name":"Stop","session_id":"%s"}' "$id")"
    [ "$status" -eq 0 ]
  done
  send "$(event Stop "$(printf 'a%.0s' $(seq 1 200))")"
  [ ! -e "$BATS_TEST_TMPDIR/escape.json" ]
  [ -z "$(ls -A "$ATTENTION_BUDDY_DIR" 2>/dev/null)" ]
}

@test "broken input exits 0 silently and writes nothing" {
  for input in '' 'not json' '{"hook_event_name":' '[1,2,3]'; do
    send "$input"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  [ -z "$(ls -A "$ATTENTION_BUDDY_DIR" 2>/dev/null)" ]
}

@test "without jq the hook does nothing" {
  ATTENTION_BUDDY_JQ=/nonexistent/jq send "$(event Stop)"
  [ "$status" -eq 0 ]
  [ ! -e "$ATTENTION_BUDDY_DIR/s1.json" ]
}

@test "control characters in the title are replaced and the file stays valid JSON" {
  send "$(event UserPromptSubmit s1 ',"session_title":"Line one\nline two\u001fend"')"
  jq empty "$ATTENTION_BUDDY_DIR/s1.json"
  [ "$(state title)" = "Line one line two end" ]
}

@test "non-ASCII titles survive" {
  send "$(event UserPromptSubmit s1 ',"session_title":"Привіт – café"')"
  [ "$(state title)" = "Привіт – café" ]
}

@test "50 parallel events leave one valid state file" {
  for i in $(seq 1 50); do
    if [ $((i % 2)) -eq 0 ]; then
      printf '%s' "$(event PermissionRequest s1 "$bash_tool")" | "$HOOK" &
    else
      printf '%s' "$(event PostToolUse s1 "$read_tool")" | "$HOOK" &
    fi
  done
  wait
  jq empty "$ATTENTION_BUDDY_DIR/s1.json"
  [ "$(ls -A "$ATTENTION_BUDDY_DIR" | grep -c '\.json$')" -eq 1 ]
  [ -z "$(ls -A "$ATTENTION_BUDDY_DIR" | grep -E 'tmp|lock')" ]
}

@test "a lock left by a crashed run is taken over" {
  mkdir -p "$ATTENTION_BUDDY_DIR/.s1.lock"
  send "$(event Stop)"
  [ "$(state status)" = done ]
}

@test "a typical event takes under 150 ms, even on a slow CI machine" {
  send "$(event UserPromptSubmit)"
  start=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    printf '%s' "$(event PostToolUse s1 "$read_tool")" | "$HOOK"
  done
  end=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
  average=$(((end - start) / 10))
  echo "average: ${average} ms" >&3
  [ "$average" -lt 150 ]
}

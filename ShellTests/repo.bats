#!/usr/bin/env bats
# Repository-wide consistency checks.

ROOT="$BATS_TEST_DIRNAME/.."

@test "the version is the same in the app, the plugin and the changelog" {
  app=$(sed -n 's/.*current = "\(.*\)".*/\1/p' "$ROOT/Sources/AttentionCore/Version.swift")
  plugin=$(jq -r .version "$ROOT/.claude-plugin/plugin.json")
  changelog=$(sed -n 's/^## \[\([0-9.]*\)\].*/\1/p' "$ROOT/CHANGELOG.md" | head -1)
  [ -n "$app" ]
  [ "$app" = "$plugin" ]
  [ "$app" = "$changelog" ]
}

@test "the plugin and marketplace use the same name, which Claude Code allows" {
  plugin=$(jq -r .name "$ROOT/.claude-plugin/plugin.json")
  listed=$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")
  [ "$plugin" = "$listed" ]
  case $plugin in
    claude-* | anthropic-* | cc-plugin-*) false ;;
  esac
}

@test "every documentation link to a local file points to a file that exists" {
  cd "$ROOT"
  for doc in README.md AGENTS.md CONTRIBUTING.md docs/DESIGN.md; do
    grep -oE '\]\([^)#]+\)' "$doc" | sed 's/^](//; s/)$//' | grep -vE '^(https?:|mailto:)' |
      while read -r target; do
        base=$(dirname "$doc")
        [ -e "$target" ] || [ -e "$base/$target" ] || {
          echo "$doc links to missing $target"
          false
        }
      done
  done
}

@test "the privacy check passes" {
  run "$ROOT/scripts/check-privacy.sh"
  echo "$output"
  [ "$status" -eq 0 ]
}

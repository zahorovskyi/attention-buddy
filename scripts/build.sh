#!/bin/sh
# Builds the attention-buddy binary with swiftc directly.
#
# Installers use this instead of SwiftPM: plain swiftc only needs the Xcode Command Line Tools
# and keeps working even when a Command Line Tools update breaks SwiftPM.
#
# Usage: scripts/build.sh [--output <path>]   (default: build/attention-buddy)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
output="$root/build/attention-buddy"

while [ $# -gt 0 ]; do
  case $1 in
    --output)
      output=$2
      shift 2
      ;;
    -h | --help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc was not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
module_cache=$(mktemp -d)
trap 'rm -rf "$module_cache"' EXIT

# All three source folders compile into one module; the `#if canImport` guards in the
# sources skip the cross-module imports that SwiftPM needs.
swiftc -O -swift-version 6 \
  -target "$(uname -m)-apple-macos13.0" \
  -module-name AttentionBuddy \
  -module-cache-path "$module_cache" \
  "$root"/Sources/AttentionCore/*.swift \
  "$root"/Sources/AttentionUI/*.swift \
  "$root"/Sources/attention-buddy/main.swift \
  -o "$output"

echo "Built $output"

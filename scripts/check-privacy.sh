#!/bin/sh
# check-privacy.sh: fails if the repository contains personal data.
#
# Checks every file git would publish for email addresses (other than GitHub no-reply and
# example domains), real home-folder paths and temporary-folder paths. Words listed one per
# line in an optional, git-ignored `.privacy-denylist` file are checked too, so personal
# names or company words can be blocked without writing them into the repository.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

files=$(git ls-files --cached --others --exclude-standard | grep -vE '^(\.build|build)/' || true)
[ -n "$files" ] || {
  echo "No files to check."
  exit 0
}

problems=0

report() {
  printf '%s\n' "$1"
  problems=$((problems + 1))
}

check() {
  label=$1
  pattern=$2
  allow=$3
  matches=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -nIE "$pattern" 2>/dev/null |
    grep -vE "$allow" || true)
  if [ -n "$matches" ]; then
    report "Found $label:"
    printf '%s\n' "$matches" | sed 's/^/  /'
  fi
}

check "email addresses" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  'users\.noreply\.github\.com|@example\.(com|org|invalid)|git@github\.com|check-privacy\.sh'
check "real home-folder paths" '/Users/[A-Za-z0-9._-]+' 'check-privacy\.sh'
check "temporary-folder paths" '/private/(tmp|var)|/var/folders/' 'check-privacy\.sh'

if [ -f .privacy-denylist ]; then
  while IFS= read -r word; do
    case $word in
      '' | '#'*) continue ;;
    esac
    hits=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -nIiF -- "$word" 2>/dev/null || true)
    if [ -n "$hits" ]; then
      report "Found a word from .privacy-denylist:"
      printf '%s\n' "$hits" | sed 's/^/  /'
    fi
  done <.privacy-denylist
fi

if [ "$problems" -gt 0 ]; then
  echo "Privacy check failed: $problems problem(s)."
  exit 1
fi
echo "Privacy check passed."

#!/bin/zsh
# One command from a fresh clone to a working Iris.app:
#   1. checks this Mac can build it (Apple silicon, macOS 26, Command Line Tools),
#   2. downloads, verifies and builds the bundled helpers (scripts/fetch-tools.sh, ~5 min once),
#   3. builds dist/Iris.app (scripts/bundle.sh).
#
# Usage: scripts/install.sh              build dist/Iris.app
#        scripts/install.sh --install    also copy it to /Applications (or ~/Applications)
set -euo pipefail
cd "${0:a:h}/.."

fail() { print -u2 -- "error: $1"; exit 1; }

[[ $(uname -m) == arm64 ]] || fail "Iris needs a Mac with Apple silicon (M1 or later)."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 26 )) || fail "Iris needs macOS 26 or later (this Mac runs $(sw_vers -productVersion))."
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null; then
  fail "Apple's Command Line Tools are missing. Run: xcode-select --install, then try again."
fi

scripts/fetch-tools.sh
scripts/bundle.sh

if [[ ${1:-} == --install ]]; then
  dest=/Applications
  [[ -w $dest ]] || { dest=$HOME/Applications; mkdir -p "$dest"; }
  rm -rf "$dest/Iris.app"
  ditto dist/Iris.app "$dest/Iris.app"
  print "Installed $dest/Iris.app. Open it with: open \"$dest/Iris.app\""
else
  print "Built dist/Iris.app. Open it with: open dist/Iris.app"
fi

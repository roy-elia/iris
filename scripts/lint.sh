#!/bin/zsh
# Lints with swift-format (ships with the Swift toolchain). Pass --fix to reformat in place.
set -euo pipefail
cd "${0:a:h}/.."

paths=(Sources Tests Package.swift)
if [[ "${1:-}" == "--fix" ]]; then
  swift format format --in-place --recursive "${paths[@]}"
fi
swift format lint --strict --recursive "${paths[@]}"

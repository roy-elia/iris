#!/bin/zsh
# Runs the swift-testing suite. With only the Command Line Tools installed (no Xcode),
# SwiftPM does not put swift-testing on the search path, including for its generated
# test runner, so pass the paths to every target here.
set -euo pipefail
cd "${0:a:h}/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
args=()
if [[ ! -d /Applications/Xcode.app && -d $CLT/Frameworks/Testing.framework ]]; then
  args=(
    -Xswiftc -F -Xswiftc "$CLT/Frameworks"
    -Xlinker -rpath -Xlinker "$CLT/Frameworks"
    -Xlinker -rpath -Xlinker "$CLT/usr/lib"
  )
fi

exec swift test --disable-xctest "${args[@]}" "$@"

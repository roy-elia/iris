# Iris

A macOS menu-bar utility: drop files on its panel to convert images, strip image metadata,
build PDFs, and share the results.

Requires macOS 14+ and Swift 6 (Xcode or the Command Line Tools).

## Run

```bash
swift build
scripts/bundle.sh        # builds dist/Iris.app
open "dist/Iris.app"
```

## Test and lint

```bash
scripts/test.sh          # swift-testing suite
scripts/lint.sh          # swift-format lint (scripts/lint.sh --fix to reformat)
```

`scripts/test.sh` wraps `swift test`. Without Xcode it adds the Command Line Tools' swift-testing
paths, which SwiftPM does not find on its own.

See SETUP.md for the spec, assumptions, dependencies and known gaps.

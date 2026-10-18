# File Drop Utility: setup and status

A from-scratch macOS menu-bar file utility. It is built from the functional spec below and
uses no code, assets, text, branding or bundled tools from any existing product.

## Stack and versions

| Item | Version |
|---|---|
| macOS (build host) | 26.6.2, Apple Silicon |
| Swift | 6.3.3 (Command Line Tools; Xcode not installed) |
| UI | SwiftUI `MenuBarExtra`, AppKit for open panels, sharing and Finder |
| Core | Foundation, ImageIO, Core Graphics, PDFKit, ServiceManagement |
| Tests | swift-testing (ships with the toolchain) |
| Lint | swift-format 6.3.0 (`swift format`, ships with the toolchain) |
| Minimum macOS for the app | 14.0 |

Why this stack: a native menu-bar app needs AppKit or SwiftUI. ImageIO and PDFKit cover every
operation in the spec with no third-party code, and SwiftPM works without Xcode.

## Spec (as built)

1. Menu-bar-only app (no Dock icon). The status item opens a panel with Files, History and Settings tabs.
2. Drop files on the panel, or click Choose Files. Each queued file shows its name, type and size and can be removed. Unsupported files and folders are rejected with a message.
3. Convert images between PNG, JPEG, HEIC and TIFF. The quality slider (10–100%) applies to JPEG and HEIC.
4. Strip metadata: writes a copy with no EXIF, GPS, TIFF (camera), IPTC or XMP data. Orientation is baked into the pixels.
5. Merge two or more PDFs in drop order, or turn images into a PDF with one page per image.
6. Results panel: Show in Finder, AirDrop, and the system Share sheet.
7. Outputs never overwrite. A collision becomes `name (1).ext`, `name (2).ext`, and so on. Outputs go next to the original or to a chosen folder.
8. Settings for default format, default quality, output location and launch at login, saved to `~/Library/Application Support/FileDropUtility/settings.json`.
9. History of the last 50 operations (newest first), saved to `history.json` in the same folder.

Output names: convert gives `name.<new ext>`; strip gives `name no-metadata.<ext>`; merge gives `Merged.pdf`; images to PDF gives `name.pdf` for one image or `Images.pdf` for several.

## Assumptions (my reading where the spec was open)

- Neutral name "File Drop Utility", bundle ID `local.filedroputility`, SF Symbols and system colours only.
- Inputs are recognised by file extension: png, jpg/jpeg, heic/heif, tif/tiff and pdf. Anything else is rejected at drop time.
- Strip metadata re-encodes at maximum quality, which is lossy for JPEG and HEIC. A lossless path would need per-format handling.
- Per-file operations keep going past a bad file and report it. Merge and images-to-PDF are all-or-nothing, and a half-written PDF is deleted.
- Password-protected PDFs are rejected, not unlocked.
- After a drop the action picker switches to a suitable operation (Merge for all PDFs, Convert for all images) only if the current choice doesn't fit.
- Out of scope: Office/Pages conversion, OCR, annotation, in-app purchases, ads, analytics.

## Acceptance criteria

| ID | Criterion | How it is checked |
|---|---|---|
| A1 | Build, full test suite and lint all pass | `swift build`, `scripts/test.sh`, `scripts/lint.sh` |
| A2 | Runs as a menu-bar-only app with no Dock icon | Test `A2` (Info.plist `LSUIElement`); `lsappinfo` reports `type="UIElement"` |
| A3 | Images convert to each format with readable output of the right type and size | Test `A3` |
| A4 | Strip metadata removes EXIF, GPS and camera fields and leaves the original unchanged | Test `A4`, `ProcessorTests` |
| A5 | PDFs merge in order with summed page count; images to PDF gives one page per image | Test `A5` |
| A6 | No output ever overwrites an existing file | Test `A6`, `OutputNamerTests` |
| A7 | Unsupported or broken files produce a message, not a crash | Test `A7` |
| A8 | Settings persist across restarts | Test `A8` |
| A9 | History keeps the last 50 operations across restarts | Test `A9` |
| A10 | Share and AirDrop open the system picker | Manual, in the running app |

## Dependencies and licences

No third-party packages. Everything is Apple system frameworks plus tools that ship with the
Swift toolchain:

| Dependency | Licence | Use |
|---|---|---|
| Apple SDK frameworks (SwiftUI, AppKit, ImageIO, PDFKit, Core Graphics, ServiceManagement) | Apple SDK licence (system frameworks) | App and core logic |
| swift-testing | Apache 2.0 with Runtime Library Exception | Tests only |
| swift-format | Apache 2.0 | Lint only |
| SF Symbols (`tray.and.arrow.down`, etc.) | Apple SF Symbols licence; usable in apps on Apple platforms | Icons |

No API keys, accounts or network calls, so there is no `.env` or `.env.example`.

## Run, test, build

```bash
cd /Users/royelia/file-drop-utility
scripts/test.sh                      # 47 tests
scripts/lint.sh                      # swift-format --strict; --fix to reformat
swift build                          # debug build
scripts/bundle.sh                    # release build, dist/File Drop Utility.app (ad-hoc signed)
open "dist/File Drop Utility.app"
swift scripts/make-samples.swift samples   # sample images/PDFs for trying it by hand
```

`scripts/test.sh` exists because without Xcode, SwiftPM doesn't put the Command Line Tools'
swift-testing on the search path, including for its generated test runner. Plain `swift test`
then builds but runs zero tests and still exits 0. The script passes the paths explicitly. I
checked that a deliberately failing test makes it exit 1.

## Toolchain fixes made on this Mac

- **Your fix, with sudo:** you moved two stale 2024 `PackageDescription.swiftmodule/*.private.swiftinterface` files into `/Library/Developer/CommandLineTools/stale-backup/`. They had broken every `Package.swift` link. The undo command is in the chat history.
- I deleted `~/Library/Application Support/FileDropUtility` before the first launch, to start clean. It is this app's own data folder.

## Known gaps against the spec

- **End-to-end UI check not done (stage 6).** Computer use can't target the app because it isn't in the Spotlight app index, and screenshot filtering hides it. `osascript` has no Accessibility permission. Verified: the app launches, runs as `UIElement` (no Dock icon) and has no crash reports or logged errors. Not verified: the status item appearing, the panel, drag and drop, the buttons, and A10. Every operation the panel runs goes through the same `Processor` the acceptance tests exercise, but the SwiftUI wiring itself is untested.
- **No window owned by the app's process was found.** On macOS 26 the menu-bar item may be hosted by another process, or hidden until allowed under System Settings > Menu Bar. See manual steps.
- Launch at login only works from the `.app` bundle (`SMAppService`). It shows an error when run with `swift run`.
- The app is ad-hoc signed, not notarized. Other Macs will block it unless you sign it with a Developer ID.
- No UI tests. XCUITest needs Xcode.

## Manual steps for you

1. Launch `dist/File Drop Utility.app` and look for the tray icon in the menu bar. If it's missing, check System Settings > Menu Bar (macOS 26) and allow "File Drop Utility". A crowded menu bar can also hide it behind the notch.
2. Run the checklist with `samples/`:
   - Drop `beach.png`, choose Convert, then JPEG, then Run. `beach.jpg` should appear.
   - Run it again. `beach (1).jpg` should appear.
   - Drop `trip.jpg`, choose Strip metadata, then Run. Finder's Get Info on `trip no-metadata.jpg` should show no location.
   - Drop `part1.pdf` and `part2.pdf`. Merge should be selected, and Run gives a 5-page `Merged.pdf`.
   - Drop `notes.txt`. It should show "is not a supported file type".
   - Click AirDrop and Share on a result. The system pickers should open (A10).
   - Change Settings, quit, relaunch. The settings should be kept, and History should list the runs.
3. Alternatively, open the app and mention it to me with `@File Drop Utility` (or give `osascript` Accessibility permission) and I'll run that checklist through the UI myself.

## Suggestions (not built)

- Lossless metadata stripping for JPEG via `CGImageDestinationCopyImageSource`.
- Batch progress for large drops, and cancel.
- Content sniffing instead of extension checks, for files without extensions.
- A Developer ID signing and notarization script.

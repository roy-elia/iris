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
| A10 | Share and AirDrop open the system picker | Stage 6 UI check (passes) |

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

## End-to-end UI check (stage 6), 2026-10-18

Run against the bundled app through macOS accessibility (System Events). You gave Claude.app
Accessibility permission for this. Files were added through Choose Files (the open panel).
Drag and drop itself wasn't simulated.

| Flow | Result |
|---|---|
| Menu-bar icon shows; app has no Dock icon (A2) | Pass. You confirmed the icon; `lsappinfo` reports `UIElement` |
| `beach.png`, Convert, JPEG, Run | Pass. 640×400 JPEG `beach.jpg`; panel shows "Saved 1 file" |
| Run again | Pass. `beach (1).jpg`; nothing overwritten |
| `trip.jpg`, Strip metadata | Pass. Copy has no GPS and no camera make; original unchanged |
| `part1.pdf` + `part2.pdf` | Pass. Action switched to Merge PDFs by itself; `Merged.pdf` has 5 pages |
| `beach.png` + `trip.jpg`, Images to PDF | Pass. `Images.pdf` has 2 pages |
| `notes.txt` | Pass. "notes.txt is not a supported file type." |
| Images plus a PDF, Images to PDF selected | Pass. Shows "works on images only" |
| AirDrop button (A10) | Pass. System AirDrop window opens |
| Share button (A10) | Pass, after a fix. The system share picker opens next to the button |
| Default format TIFF + output folder via Choose Folder, then Quit and relaunch | Pass. Both kept; next conversion defaulted to TIFF and saved into the chosen folder |
| History after relaunch | Pass. All runs listed, newest first |
| Launch at login | Not exercised. It would register a real login item on your account; ask me to test it |

Settings were put back to defaults (PNG, next to original) afterwards.

### Fixes from the UI check

- **Share button:** replaced SwiftUI `ShareLink` with an AppKit `NSSharingServicePicker` button (`ShareButton.swift`). The replacement is verified to open the picker. I didn't confirm whether the original `ShareLink` was actually broken; my first check only looked for an in-app menu, and this picker is not one.
- **Settings layout:** "Choose Folder…" was missing from the accessibility tree (probably clipped in the form's narrow right-hand column). It now sits on its own row and shows up.
- **Accessibility:** the drop zone had merged with its Choose Files link into one unlabeled element; it's now a labeled container with a separate button. The decorative tray image is hidden from VoiceOver. Key controls have accessibility identifiers, which the UI check uses.

## Known gaps against the spec

- Drag and drop onto the panel wasn't simulated; files went in through the open panel, which feeds the same `add` path.
- Launch at login wasn't exercised (see above). It only works from the `.app` bundle (`SMAppService`).
- The app is ad-hoc signed, not notarized. Other Macs will block it unless you sign it with a Developer ID.
- No automated UI tests. XCUITest needs Xcode; the stage 6 check was scripted by hand and isn't in the repo.

## Manual steps for you

- Optional: try a real drag and drop from Finder onto the panel.
- Optional: toggle Launch at login, check it appears under System Settings > General > Login Items, then toggle it off.
- If you want to undo the Accessibility permission, turn Claude off in System Settings > Privacy & Security > Accessibility.

## Suggestions (not built)

- Lossless metadata stripping for JPEG via `CGImageDestinationCopyImageSource`.
- Batch progress for large drops, and cancel.
- Content sniffing instead of extension checks, for files without extensions.
- A Developer ID signing and notarization script.

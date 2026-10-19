# File Drop Utility: setup and status

A from-scratch macOS menu-bar file utility with a Liquid Glass interface. The layout takes
structural cues from screenshots you supplied: an onboarding carousel, radial action wheels,
modifier-key hints and a status header. It reproduces no other product's name, icon, colours,
wording, code or bundled tools.

## Stack and versions

| Item | Version |
|---|---|
| Minimum macOS | **26.0** (Liquid Glass APIs are macOS 26+) |
| Build host | macOS 26.6.2, Apple Silicon |
| Swift / tools | Swift 6.3.3, `swift-tools-version:6.2`, Command Line Tools (no Xcode) |
| UI | SwiftUI (`MenuBarExtra`, Liquid Glass), AppKit for windows, panels, sharing and event monitors |
| Core | Foundation, ImageIO, Core Graphics, Core Image, PDFKit, Vision, ServiceManagement |
| Tests / lint | swift-testing, swift-format (both ship with the toolchain) |

## Features

**Menu-bar menu:** a native macOS menu with the status line ("File Drop Utility is ready"), the ⇧ ⌘ ⌃ hints, Settings… (⌘,), Getting Started…, About and Quit (⌘Q).

**Main window** (from Settings…): a status header, a floating glass tab bar (Files, History, Settings), and floating glass cards.
- **Files:** drop zone and Choose Files, the queued list with sizes, three wheel launchers, and the last result with Show in Finder, AirDrop and Share.
- **History:** the last 50 operations.
- **Settings:**
  - Appearance (System, Light or Dark; System by default)
  - Default format and quality
  - Save location
  - Wheels while dragging
  - Launch at login

**Wheels** open from the panel, or by holding a modifier while dragging files from another app:

| Wheel | Key | Segments |
|---|---|---|
| Convert | ⇧ Shift (configurable) | PNG, PDF, JPEG, HEIC, AVIF, TIFF, BMP, WebP (bundled cwebp), GIF (animations keep every frame), ICO (16–256 px), ICNS (16–1024 px), JPEG 2000, TGA, OpenEXR. Inputs also include SVG, camera RAW (CR2, CR3, NEF, ARW, DNG, RAF, ORF and the other RAWs ImageIO reads), PSD, PPM/PGM/PBM and Radiance HDR. |
| Tools | ⌘ Command (configurable) | Compress (presets or a target size), Metadata (view, edit, remove location, strip), Annotate, Redact, Crop (one or many images), Add BG (remove, colour or image), Frame, Collage, QR Code, Resize (longest side in px, or %), Grayscale, Adjust |
| Actions | ⌃ Control | AirDrop, Float, Copy, Move, Copy Path, Zip (any files or folders into one archive), Terminal |

A segment is disabled, with the reason as a tooltip and VoiceOver hint, when the queued files don't fit it. Press the modifier any time during the drag, even with the pointer still. Switching modifiers switches the wheel. Letting go of the key closes the wheel unless you're over it, and Escape closes it. While dragging over the overlay wheel, the segment under the pointer lights up in the accent colour with a soft glow, the centre pill shows its name, and a soft tick plays (with a trackpad tap). A drop plays a pop, runs the command, and reports the result in a glass toast at the top of the screen.

**Video** (when every dropped file is a video: MP4, MOV, M4V, WebM, MKV, AVI, WMV/ASF, FLV, MPEG, TS, M2TS/MTS, 3GP, OGV, VOB):
- **Convert wheel:** MP4, HEVC (H.265 MP4 from the hardware encoder, saved as "name HEVC.mp4"), 720p (H.264 MP4 at most 720 px high, "name 720p.mp4"), MOV, M4V, MKV, AVI, WebM (VP9 + Opus), GIF (palette-optimised, 15 fps), and MP3 or M4A audio.
- **Tools wheel:** Compress (Light, Medium or Strong, or a target size), Trim, Split, Join, Speed, Frames, Crop, Redact, Subtitles (each text subtitle track saved as SRT, named by language when there are several).
- **Video editor:**
  - the picture fills the window, with a glass timeline of thumbnails under it
  - tools: trim handles, split points with removable clips (export separately or join what's kept), speed 0.25–4×, frame snapshots as PNG, crop, and timed redactions (solid, pixelate or blur, each with its own time range)
  - files AVFoundation can play get live playback (Space); others get still frames while scrubbing
- **Join window:** set the order. Videos of different sizes are fitted to the first one's frame, and silent clips get a silent track.
- Encoding uses Apple's hardware H.264 encoder through the bundled ffmpeg; progress shows in the status menu, and Stop Current Task cancels.

**Audio** (when every dropped file is audio: MP3, WAV, M4A, AAC, FLAC, AIFF, OGG, Opus, WMA, CAF, AMR, APE, AC-3):
- **Convert wheel:** MP3, M4A, AAC, WAV, AIFF, FLAC, OGG (Vorbis), Opus, AMR (narrowband, 8 kHz mono, 12.2 kbps), AMR-WB (.awb, 16 kHz mono, 23.85 kbps) and APE (Monkey's Audio, lossless). Videos can be converted to audio too. Bit depth (WAV 16/24/32; AIFF, FLAC and APE 16/24) and bitrate are set per format under Settings › Audio defaults; AMR's speech rates are fixed.
- **Tools wheel:** Trim, Bleep, Volume, Channels (the audio editor), and Visualizer.
- **Audio editor:**
  - a large glass waveform with the playhead and live playback where AVFoundation can play the file
  - Trim: drag the ends, or set them at the playhead; "Trim silent ends" with a threshold slider (−80 to −20 dB)
  - Bleep: add ranges and drag their ends, or bleep the whole file (a 1 kHz tone replaces the sound)
  - Volume: normalize loudness (EBU R128) to −14, −16 or −23 LUFS
  - Channels: keep, mono or stereo, with a left/right balance
  - every tool's settings go into one saved copy ("name edited.ext")
- **Visualizer window:** wave, bars or spectrum, 16:9, 1:1 or 9:16, a wave colour, and a solid colour or image behind it. Saves "name visualizer.mp4".

**Documents** (DOCX, DOC, ODT, RTF, RTFD, TXT, Markdown, HTML, EPUB, Pages, text clippings; CSV/TSV tables; Keynote, PowerPoint, Numbers, Excel and ODS):
- **Convert wheel:** PDF, DOCX, RTF, Text, Markdown, HTML, EPUB, Pages. Presentations and spreadsheets convert to PDF.
- Markdown is converted by a built-in parser (headings, emphasis, lists, quotes, code, tables, links). Remote images, scripts and stylesheets are stripped from HTML before it's read, so nothing is fetched.
- EPUB out is reflowable EPUB 3, with a chapter at each top-level heading. EPUB in reads the spine in order, after checking the archive for unsafe paths and size.
- Pages, Keynote and Numbers: exported by the app through AppleScript when it's installed; otherwise the document's saved preview, or a Quick Look rendering of the first page. Writing Pages documents needs Pages.

**PDFs:**
- **Convert wheel:** PNG or JPEG pages (144 dpi), TIFF (every page in one multi-page TIFF), CBZ (a comic-book zip of JPEG pages), DOCX, RTF, Text, Markdown, HTML, EPUB, and "EPUB Pages" (fixed layout, one image per page).
- Pages without selectable text are read with Vision OCR.
- **Tools wheel:** Organize, Split (one PDF per page, or page ranges such as "1-3, 7, 9-"), Compress, Merge. The organizer is a thumbnail grid: drag or use the arrows to reorder, turn pages, delete them (⌫), and optionally scale every page to the same width.

**Data** (JSON, XML, property lists, vCards, and CSV tables): the Convert wheel offers JSON → CSV, XML or Plist; CSV → JSON or vCard (alongside the document outputs); XML → JSON; Plist → JSON; vCard → CSV.
- JSON → CSV takes the top-level array of records (or the first array inside a top-level object); nested objects become "a.b" columns and arrays are written as JSON. CSV → JSON keeps every value as text.
- XML → JSON: attributes become "@name" keys, repeated elements become arrays, and text beside child elements is "#text". External entities are never loaded.
- vCard ↔ CSV uses Name, Given Name, Family Name, Organization, Title, Email, Phone, Address, Birthday, URL and Note columns; common header spellings ("First Name", "E-mail Address", "Mobile", "Company") are recognised. Several emails or phones share a cell, separated by "; ".

**Subtitles:** SRT, VTT, ASS, SSA, SAMI (.smi) and LRC, each to any of the others. ASS/SSA bold and italic overrides become tags; SAMI keeps its first language class; LRC lines last until the next line. Files that aren't UTF-8 (such as Korean CP949 SAMI files) are decoded from the likeliest legacy encoding. **Archives:** zip, CBZ, 7z, tar, tar.gz/tgz, tar.bz2, tar.xz and ISO → a folder next to it; a single .gz, .bz2 or .xz file → the file inside. Every archive is checked first for unsafe paths, more than 20,000 files, or more than 2 GB unpacked (zip with ditto, the rest with macOS's bsdtar).

**Shell:**
- **Floats:** the Actions wheel's Float puts the files in a glass tab tucked against the right screen edge (Add to Float adds to the latest one). Hover to open it into a stack. Drag the tab or its header to carry every file, drag a row for one file, double-click to open, right-click for Open, Show in Finder, Copy Path, Remove from Float and Close Float. Drag the grip to move it; it snaps to the nearer edge. Drop files on a Float to add them. Floats are saved and come back after a relaunch; closing one never touches the files.
- **Wheel themes:** Regular (default), Clear and Tinted Liquid Glass, under Settings.
- **Update check:** off by default. It needs a build made with `UPDATE_FEED_URL=https://…/releases/latest scripts/bundle.sh`; then Settings › "Check for updates daily" looks once a day, and a newer release adds "Update Available" to the menu. Builds without a feed never make the call.
- **Onboarding** has a page showing what the wheels do for each kind of file.

**Tool windows** (floating glass panels opened from the Tools wheel):
- **Compress:** Smallest, Balanced or Best quality presets, or a target size in KB/MB. Each file is compressed to the target or below, separately. Dimensions shrink only when even the lowest quality is too big.
- **Metadata:** edit Title, Description, Artist, Copyright, Keywords and Date taken; remove location; browse every field; or strip all. Uses the bundled ExifTool.
- **Background:** remove it (transparent PNG), or put the subject on a colour or an image.
- **Frame:** padding, rounded corners and a shadow on a gradient, solid or transparent background, in a free shape or 1:1, 4:3, 16:9, 4:5 or 9:16.
- **Collage:** an automatic or fixed-column grid with spacing, corners, background colour, fill or fit, name order, and 1200, 2400 or 4000 px width.
- **QR codes:** every code in the image, with Copy, plus Open for links.

**Other windows:**
- **Editor:**
  - adjust brightness, contrast and saturation
  - crop, optionally applying the same crop to every dropped image
  - annotate: draw, arrow, rectangle, ellipse, highlight, text, numbered callouts, magnifier bubble, image sticker
  - redact: solid, pixelate or blur
  - rotate and undo
  
  Save Copy writes `name edited.ext` and never touches the original.
- **Float:** an always-on-top glass card per file. Move it by its header; drag the preview to drop the file somewhere else.
- **Onboarding:** six pages shown on first launch and from Getting Started: Welcome, the three wheels with key caps, folder access, and Finish (launch at login and the wheel toggle).

**Output names:** `name.ext` (convert), `name edited.mp4`, `name part 1.mp4`, `Joined.mp4`, `name 0m01.5s.png` (video frames), `name no-metadata.ext`, `name metadata.ext`, `name compressed.ext`, `name no-bg.png`, `name edited.ext`, `name framed.png`, `Collage.png`, `Merged.pdf`, `Images.pdf`. Existing files are never overwritten; a collision becomes `name (1).ext`.

## Design system

All adaptive values live in one file. Change them there and every screen follows.

| Component | File |
|---|---|
| Tokens: radii, insets, blue-teal accent, secondary/error/warning text, legibility backing, contact and ambient shadows, spring and fade | `Sources/FileDropUtility/Design/DesignTokens.swift` |
| `glassPanel()` / `glassCard()`, prominent and subtle glass buttons, `Keycap`, `withMorph`, the Increase Contrast override | `Sources/FileDropUtility/Design/GlassStyles.swift` |
| Floating tab bar (morphing selection) | `Sources/FileDropUtility/Design/FloatingTabBar.swift` |
| Radial wheel, ring segment shape, shared wheel geometry | `Sources/FileDropUtility/Wheel/RadialWheel.swift` |
| AppKit drop target, hover state, sounds and haptics | `Sources/FileDropUtility/Wheel/WheelDrop.swift` |
| Drag trigger rules (unit-tested) | `Sources/DropCore/DragTrigger.swift` |
| Segment hit-testing (unit-tested) | `Sources/DropCore/WheelHitTest.swift` |
| Wheel definitions, overlay, drag watcher, toast | `Sources/FileDropUtility/Wheel/WheelModel.swift`, `WheelOverlay.swift` |
| Panel screens | `Sources/FileDropUtility/Panel/` |
| Editor | `Sources/FileDropUtility/Editor/` |
| Onboarding, Float, window manager, snapshot harness | `Sources/FileDropUtility/Windows/` |
| Previews | `Sources/FileDropUtility/Previews.swift` |

### How each design requirement is met

1. **Materials:** every primary container uses `glassEffect(_:in:)` with `Glass.regular`, plus `.tint(_:)` and `.interactive()` where relevant. `GlassEffectContainer` groups the tab bar and the editor toolbar, and `glassEffectID(_:in:)` morphs the tab selection. There are no opaque container backgrounds. The only opaque fallback is when **Reduce Transparency** is on, which swaps glass for the window background colour.
2. **Shapes:** `RoundedRectangle(cornerRadius:style: .continuous)`, `Capsule(style: .continuous)` and `Circle` only. `.cornerRadius()` appears 0 times. Wheel segments are ring sectors (a custom `Shape`), since a wheel can't be built from rectangles.
3. **Floating layout:** cards, the tab bar, the editor toolbar and inspector, the toast and the onboarding panel all sit inset from the window edges (`Spacing.inset` = 12pt). Onboarding, Float and the overlay use transparent windows, so only the glass is drawn.
4. **Depth:** a tight contact shadow (radius 1.5, y 1) plus a soft ambient shadow (radius 22, y 12). Opacity is 0.12 / 0.10 in light mode and 0.50 / 0.45 in dark mode.
5. **No outlines:** nothing draws a stroke around glass. Edges come from the Liquid Glass material's own specular rim plus the two shadows. The lit wheel segment glows in the accent colour instead of being outlined.

6. **Motion:** every animation goes through `DesignTokens.Motion`. It's a spring (response 0.4, damping 0.7) normally, and a 0.2s fade and opacity transition under **Reduce Motion**. A grep confirms no animation bypasses the tokens.
7. **Light and dark:**
   - Text uses `.primary` plus tokens built on the label colours.
   - Custom colours have light, dark and high-contrast variants defined in code.
   - The system switches appearance live; the app forces one only if you pick Light or Dark in Settings.
8. **Accessibility:**
   - Every control has a VoiceOver label (wheel segments carry their disabled reason as a hint) and an accessibility identifier.
   - Decorative images are hidden from VoiceOver.
   - Increase Contrast strengthens the legibility backing, and switches to the high-contrast colour variants.
   - Dynamic Type: see Known gaps.

### Contrast work (WCAG AA, 4.5:1 body text)

Every screen was rendered in a real window over a deliberately busy, bright backdrop, in light, dark, light + Increase Contrast and dark + Increase Contrast. Then Vision OCR found every text line, and each line's contrast was measured from the pixels.

The first pass found failures, each fixed in the design tokens:

| Problem | Fix |
|---|---|
| Text on glass dropped to 3.6–4.4:1 over bright content | Each glass panel gets a thin layer of the window background colour (50–55%, or 85% with Increase Contrast). The glass still shows through. |
| System `.secondary` is 50% black, about 3.9:1 even on white | A `secondaryText` token: 64% in light, 66% in dark, 80% and 82% with Increase Contrast |
| System red and orange were too light for small text | `errorText` and `warningText` tokens |
| White on the blue-teal button measured 3.95:1, because the glass highlight lightens the fill | The fill was darkened; it now measures 5.7–6.2:1 |

**Final scan:** 869 text lines measured. Every line of app text is ≥ 4.5:1 in all four appearances. The remaining hits are OCR fragments of the backdrop's own "Busy text" and one icon.

Increase Contrast can't be switched on per window, so the snapshots use macOS's high-contrast appearances plus an app-level `forceIncreasedContrast` environment value that the glass styles honour.

## Assumptions

- macOS 26 minimum, as you chose, so no material fallback is needed for missing APIs. Reduce Transparency still gets an opaque fallback.
- The wheels open globally while dragging from other apps; it can be turned off in Settings. Drags that start inside this app don't trigger them, because AppKit's drag loop consumes those events.
- Editor tools work on one image at a time. Wheel tools on several files edit the first image.
- Rotating in the editor clears that edit's redactions, strokes and crop, rather than guessing how to rotate them.
- The menu-bar icon opens a native menu, as in your screenshot; the Files, History and Settings content moved to a window opened by Settings…. Left out of the menu: the free-uses line and Unlock, since there's no licensing.
- The hover sound is the app's own highlight tap, synthesised in code (`DropCore/HighlightSound.swift`: a soft D6 + A6 tap, 75 ms, fading out); the drop sound is the system Pop. No third-party sound files are used.
- Not built: licensing, free-use counts and purchases from the screenshots. You asked for features, and a paywall would need a payment account.

## Dependencies and licences

No third-party Swift packages. Five command-line helpers are bundled as separate executables, fetched and built by `scripts/fetch-tools.sh`. That script uses pinned versions from the official sites and checks each SHA-256. The ffmpeg and WebP archives were also GPG-verified when first downloaded (2026-10-18).

| Dependency | Licence | Use |
|---|---|---|
| Apple SDK frameworks | Apple SDK licence | App and core |
| ffmpeg 9.0.2 + ffprobe, built from source **LGPL-only** (`--disable-gpl --disable-nonfree --disable-autodetect`), links only macOS system libraries | LGPL v3 | Audio and video (phases 2–3) |
| LAME 3.100, static inside ffmpeg | LGPL v2 | MP3 encoding |
| libvpx 1.17.0, static inside ffmpeg (tag cloned from chromium.googlesource.com/webm/libvpx; commit 6df3ec34… matched against the github.com/webmproject mirror) | BSD-3-Clause + patent grant | VP8/VP9 for WebM output |
| opencore-amr 0.1.6 and vo-amrwbenc 0.1.3, static inside ffmpeg (sourceforge.net/projects/opencore-amr; hashes match Homebrew's pinned ones) | Apache 2.0 | AMR-NB and AMR-WB output (ffmpeg is built `--enable-version3`, so LGPL v3) |
| Monkey's Audio SDK 13.30 (monkeysaudio.com), its `mac` tool compiled with clang++ | 3-Clause BSD (Monkey's Audio License Agreement) | APE output (2026-10-19). The site publishes no checksum, so the pinned SHA-256 is the download's. |
| cwebp 1.6.0 (Google's signed macOS arm64 build) | BSD-3-Clause + patent grant | WebP export (phase 1) |
| ExifTool 13.59, run with macOS's `/usr/bin/perl` | Artistic or GPL (Perl terms) | Metadata view/edit (phase 1) |
| swift-testing | Apache 2.0 with Runtime Library Exception | Tests |
| swift-format | Apache 2.0 | Lint |
| SF Symbols | Apple SF Symbols licence | Icons |

Licences and source URLs ship in the app at `Contents/Resources/Licenses` (`SOURCES.txt` lists versions and hashes). The LGPL lets you swap in your own ffmpeg build: replace `Contents/Helpers/ffmpeg`.

Verification note: the WebP release key (fingerprint 6B0E 6B70 976D E303 EDF2 F601 F9C3 D6BD B823 2B5D) came from keyserver.ubuntu.com, because Google's download page doesn't publish it. The signature matched it.

There are no API keys or network calls at runtime, so there is no `.env`.

## Run, test, build

```bash
cd /Users/royelia/file-drop-utility
scripts/fetch-tools.sh          # once: download, verify and build the helpers into Vendor/ (~5 min)
scripts/test.sh                 # 189 tests (tool tests skip if Vendor/out is missing)
scripts/lint.sh                 # swift-format --strict
swift build
scripts/bundle.sh               # dist/File Drop Utility.app (ad-hoc signed), helpers included
open "dist/File Drop Utility.app"
.build/debug/FileDropUtility --snapshot /tmp/fdu-snaps          # all screens × 5 appearances
.build/debug/FileDropUtility --snapshot /tmp/fdu-snaps --only Editor
```

Two scripts work around missing Xcode pieces:
- `scripts/test.sh` adds the Command Line Tools' swift-testing paths. Without it, `swift test` runs zero tests and still passes.
- The snapshot mode needs Screen Recording permission for the app that runs it.

## Previews

`Previews.swift` uses `PreviewProvider`. The `#Preview` and `@Entry` macros need plugins that ship only with Xcode, so they don't compile here.

It covers every screen in Light, Dark and Largest Text: Panel (Files, History, Settings), the three wheels, a drag hovering over the Actions wheel (Terminal lit), Onboarding (Welcome, Tools, Finish), Toast, Editor and Float. Xcode shows them in the canvas.

Without Xcode, the snapshot harness renders the same screens in real windows. Glass only composites in live windows, not in offscreen `ImageRenderer` output.

## Verified in the running app

- First launch opens onboarding; clicking through all six pages and Done saves the "completed" flag.
- Files are added through the panel; the Actions wheel opens; Float opens an always-on-top card.
- A real Shift-drag of `trip.jpg` from Finder (synthesised HID events) showed the 380×380 Convert overlay under the pointer.
- The floating card no longer moves when you drag its image; it starts a file drag. (Found and fixed during this check.)

- The native menu shows all eight items with the right enabled states and shortcuts (read back through Accessibility and captured in `docs/previews/Menu.png`).
- A synthesised drag from a test window, then ⇧ pressed with the pointer still, opens the Convert wheel under the pointer; releasing ⇧ closes it. (It failed before: macOS 26 hides the drag pasteboard's types from other apps, so the watcher never recognised the drag. Fixed.)

Confirmed by you by hand (2026-10-18): a real drag with the redrawn wheel looks and feels like the reference. Synthesised events can't drive a drag session on this Mac, so that hand test is the end-to-end check.

## Feature self-test

`.build/debug/FileDropUtility --selftest <folder>` (debug builds) makes sample files of every kind (images including a camera-RAW DNG, PSD, TGA, OpenEXR, ICO and HDR; QR; SVG; video in MP4, MOV, MKV with a subtitle track, WMV, FLV, MPEG, TS, 3GP, OGV and VOB; audio including AC-3, AMR and APE; PDFs including a scanned page; Word, RTF, Markdown, HTML, CSV, JSON, XML, plist and vCard; a text clipping; SRT, VTT, ASS, a CP949 SAMI and LRC subtitles; zip, 7z, tar.gz, ISO and a single .gz) and runs every wheel segment for each: operations through the Processor with their outputs checked, window segments by opening the window and running what it saves, and actions by their effect (clipboard, Floats). The clipboard is restored afterwards. `FDU_SELFTEST_ONLY=png/Metadata` narrows it. The last run is in `docs/FEATURE-TEST.md`: 857 passed, 0 failed, 26 correct refusals (for example "No QR codes found" on a photo, or "has no subtitle tracks" on a video without any); AirDrop, Move and Terminal are skipped because they open system UI. Each segment has a 120-second watchdog (`FDU_SELFTEST_TIMEOUT` overrides it): a segment that hangs is reported as a failure and the run continues, so the report is always written. Camera RAW is exercised with a generated DNG (an uncompressed Bayer mosaic that ImageIO decodes as RAW).

Bugs it found, now fixed:
- Opening the Metadata window crashed the app. Tool windows and the main window sized themselves live to their content, and a height change after opening sent AppKit into an endless constraints loop. Windows now size from a measured ideal size.
- Metadata was offered for SVG files, which ExifTool can't write.
- The Files tab still said "Drop images or PDFs here".
- The Settings tab now scrolls instead of running off small screens.

## Known gaps

- **Floats:** dragging out of a Float, hover-to-open and edge snapping need a real pointer, so they're checked by snapshots and unit tests (placement, snapping, persistence), not end to end. The update check has no feed configured, so only its parsing and version logic are tested.
- **Documents:** Pages, Keynote and Numbers aren't installed on this Mac, so the scripting paths (Pages output, iWork and Office → PDF through the apps) are untested; the preview and Quick Look fallbacks are tested. PDF output from text is laid out on US Letter pages. Images inside documents survive DOCX/RTF/PDF output but not Markdown, HTML or EPUB output.
- **Audio:** OGG, Opus and WMA can't play in the editor (AVFoundation doesn't read them); the waveform and every edit still work. Ogg Vorbis and Opus use ffmpeg's own encoders, which are adequate rather than best-in-class (libvorbis and libopus aren't bundled). Normalize is single-pass loudnorm, accurate to about ±1 LU on typical material.

- **WebP export:** macOS's ImageIO reads WebP but can't write it. WebP files work as inputs; the WebP segment is disabled with that reason. Export would need libwebp (BSD licence), which I'd add only with your OK.
- **Dynamic Type:** SwiftUI text styles on macOS don't respond to `dynamicTypeSize`. The Largest Text snapshots look the same as normal. Views use text styles throughout, so they'll scale wherever the OS scales them, but macOS 26 offers no system-wide Dynamic Type to test.
- **Increase Contrast and Reduce Motion:** checked by simulation (high-contrast appearances, the contrast override, and a code audit of all animations), not by toggling the system settings.
- **Launch at login:** not exercised, because it registers a real login item.
- **Signing:** ad-hoc signed, not notarized.
- **UI tests:** none automated; XCUITest needs Xcode.

## Manual steps for you

1. **Wheel drop test (2 minutes):** drag any image from Finder, hold ⇧ while dragging, move over the segments (each should light up with a tick), and drop on **JPEG**. You should hear a pop, and a glass toast should say "saved 1 file". Then try ⌘ (Tools) and ⌃ (Actions).
2. Optional: try the app with System Settings › Accessibility › Display › Increase Contrast, Reduce Transparency and Reduce Motion turned on.
3. Optional: toggle Launch at login and check System Settings › General › Login Items.
4. Optional: revoke the Accessibility and Screen Recording permissions you gave Claude, in System Settings › Privacy & Security.

## Suggestions (not built)

- WebP export via libwebp.
- Lossless JPEG metadata stripping.
- A bespoke app icon (it currently uses the system tray symbol).
- Per-file progress for large batches.

# UI revision: Liquid Glass polish, drag-and-drop, menu

Implementation notes for the revision that followed the Tangerine dropdown screenshot and the sample drag video.

## Mockups

| Mockup | File |
|---|---|
| Menu-bar dropdown (captured from the running app) | `docs/previews/Menu.png` |
| A drag hovering over the Actions wheel, Terminal lit | `docs/previews/Wheel-DropHover.png` |
| The three wheels, no outlines | `docs/previews/Wheel-Convert.png`, `Wheel-Tools.png`, `Wheel-Actions.png` |
| Main window (Files, History, Settings) | `docs/previews/Panel-*.png` |
| Onboarding, Editor, Float, Toast | `docs/previews/Onboarding-*.png`, `Editor.png`, `Float.png`, `Toast.png` |

Each sheet shows light, dark, light + Increase Contrast, dark + Increase Contrast and dark + largest text, over a deliberately busy backdrop.

## What the video showed

- The user drags a file from Finder and holds a modifier. The wheel appears at the pointer and stays put.
- The segment under the pointer fills solid in the accent colour with white text and icon. The others stay dark glass.
- No segment has an outline.
- The centre pill shows the hovered segment's name.
- After the drop, the result appears next to the original file.
- The recording has no audio track, so the sound itself couldn't be matched.

## Changes

### 1. No outlines
- Deleted `DesignTokens.Stroke` and every overlay that used it: `GlassPanel`, the wheel segments and `Keycap`.
- Edges now come only from the Liquid Glass material's specular rim and the existing contact and ambient shadows.
- `Keycap` is a small glass chip instead of an outlined grey box.

### 2. Drag-and-drop
- **Why the old version failed:**
  - The drag watcher checked whether the drag pasteboard held file URLs. On macOS 26, pasteboard privacy hides those types from apps that aren't the drop target, so the check never passed and the wheel didn't open.
  - SwiftUI's per-segment `onDrop` also never received drops in the live test.
- **Detection** (`WheelOverlay.swift`):
  - A change-count bump on the drag pasteboard during a mouse drag now counts as a drag.
  - It's ruled out only when the types are readable and contain no file URL.
- **Drop target** (`WheelDrop.swift`):
  - `WheelDropView`, a transparent AppKit view over the wheel, calls `registerForDraggedTypes([.fileURL])`.
  - `draggingEntered` and `draggingUpdated` work out the segment from the angle and distance to the centre.
  - It returns `.copy` over an enabled segment and no operation elsewhere, so the cursor shows where a drop will work.
  - `performDragOperation` reads the file URLs and runs the segment's command once the drag session finishes.
- **Shared geometry:**
  - `WheelGeometry` (SwiftUI) and `WheelHitTest` (DropCore) use the same start angle and inner ratio, so the lit segment is always the one under the pointer.
  - `WheelHitTest` has unit tests for order, the centre hole, the rim and boundaries.

### 3. Hover illumination
- The drop view publishes the hovered segment through `WheelDropState`.
- `RadialWheel` takes it as `hotID`. The lit segment then:
  - fills with the accent colour, tinted glass and white text
  - glows (an accent shadow of radius 14 instead of an outline)
  - scales up by 4% with the spring, or doesn't scale under Reduce Motion
- The centre pill swaps "Drop" for the segment's name.
- In click mode (the main window and onboarding), pointer hover does the same.

### 4. Sound and haptics
- **Hover:** the system "Tink" at 45% volume, plus an alignment haptic on Force Touch trackpads.
- **Drop:** the system "Pop" at 70% volume, plus a level-change haptic.
- Sounds restart on quick moves instead of being skipped.
- They are built-in macOS sounds. Tangerine's bundled sound wasn't used.

### 5. Menu-bar dropdown
- `MenuBarExtra` switched from `.window` to `.menu` style, so it's a real macOS menu with native material, spacing, separators and shortcut glyphs.
- **Items, in the screenshot's order:**
  - status line with a checkmark (disabled)
  - modifier hints (disabled)
  - separator
  - Settings… ⌘,
  - Getting Started…
  - About File Drop Utility
  - separator
  - Quit ⌘Q
- **Left out:** the free-uses line and Unlock, since there's no licensing.
- **Settings…** opens the former panel as a transparent, content-sized glass window (`WindowManager.openMain`).

### 6. Wheel look
- The backing disc behind the segments is gone, so the segments float as separate glass pieces with a 7pt gap, as in the video.
- Each segment has its own contact and ambient shadow.
- Segments aren't wrapped in a `GlassEffectContainer`, because it melted them into one shape and hid the labels.

### 7. Drag trigger rebuilt after the first hand test

The first version reacted only to mouse events, so it felt unreliable in a real drag. Tangerine's binary was inspected for the macOS APIs and class layout it uses (names only; none of its code was copied). Its `DragGestureMonitor` polls the button state, modifier flags, Escape and the drag pasteboard's change count on a timer, with a trigger grace interval and an "is the drag inside the overlay" check. Its overlay view implements the same seven `NSDraggingDestination` methods as `WheelDropView`, and its sound player plays from a pool of copies.

Ours now works the same way, written from scratch:
- **`DragTrigger`** (DropCore, 8 unit tests) holds the rules:
  - A drag starts when the drag pasteboard changes while the button is held.
  - Holding a modifier opens its wheel at the pointer, even if the pointer isn't moving.
  - Changing modifier switches the wheel in place.
  - Letting go of the modifier closes the wheel after 0.18s, unless the drag is over the wheel.
  - Escape closes the wheel for the rest of that drag.
  - Releasing the button closes the wheel 0.25s after the drop lands.
- **`DragWatcher`** feeds it samples:
  - It reads `CGEventSource` button, flag and key state plus the drag pasteboard.
  - It samples every 80ms while idle and at 60Hz while the button is down or the wheel is open.
  - A mouse-down monitor records the change count at the exact moment of the press.
- **Overlay controller:**
  - It reuses one drop view when switching wheels, so a drag in progress isn't interrupted.
  - It fades out over 0.12s.
  - The old mouse-up timer is gone.
- **Sounds:** each sound plays from a pool of voices taken in turn (4 for the tick, 2 for the pop).

Checked live with a synthesised drag: pressing ⇧ mid-drag with the pointer still opens the Convert wheel, and releasing ⇧ closes it.

## Verification

- **Code checks:**
  - `scripts/test.sh`: 82 tests pass, including 3 hit-test and 8 drag-trigger tests.
  - `scripts/lint.sh`: clean.
  - `swift build` and `scripts/bundle.sh`: succeed.
- **Snapshots:** every preview recaptured (65 captures, 14 sheets).
- **Menu:** item names, enabled states and shortcuts read back through Accessibility from the running app.
- **Wheel opening:** a synthesised Shift-drag from a test window opens the wheel under the pointer.
- **Not verified:** a drop onto a segment. Synthesised events can't drive a drag session on this Mac; a plain AppKit test target got nothing either. One real drag by hand is needed (SETUP.md, Manual steps 1).

## Requirement summary

| Requirement | How it's met |
|---|---|
| Remove all outlines from bubble elements | Stroke token and every stroke overlay deleted. The glass rim and shadows define edges, and the lit segment glows instead. |
| Functional drag-and-drop with sound | Polling trigger modelled on Tangerine's approach: it opens on a key press without movement, switches wheels, closes on key release or Escape, and stays open while over the wheel. AppKit drop target with segment hit-testing. Pooled tick and pop sounds, plus haptics. A real drop by hand is still pending. |
| Hover illumination for the selected task | The segment under the pointer fills with the accent colour, glows and scales, and the centre names it. |
| Top-bar dropdown matching the screenshot | Native `.menu`-style menu with the same structure, order, separators and shortcuts. Licensing items left out. |
| Genuine Apple Liquid Glass | `glassEffect` on every surface, tinted glass for the lit state, free-floating segments, no strokes. Opaque only under Reduce Transparency. |
| No "temu" styling | Removed the outlines, the disc-within-a-disc wheel and the outlined keycaps. The custom panel menu is now the system menu. |
| Apple-level polish review | Every screen re-rendered in five appearances. Text contrast work from the previous round still applies (≥ 4.5:1). Spring motion and Reduce Motion fallbacks unchanged. |

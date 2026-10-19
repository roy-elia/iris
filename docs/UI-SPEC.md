# UI design specification: bubbly Liquid Glass

How every surface of File Drop Utility looks and behaves. It covers three requirements:
- Apple's menus are used exactly as Apple ships them.
- The interface is bubbly.
- The interface is transparent, reflective and liquid.

**Target:** macOS 26. Every API named here was type-checked against the installed SDK on 2026-10-18.

The "[FILL: Apple menu design guidelines]" input is filled by Apple's Human Interface Guidelines (Menus, Materials, and the macOS 26 Liquid Glass guidance) plus the SwiftUI and AppKit APIs that implement them. Using the system components *is* following the guidelines, so this spec never redraws a menu.

## 1. Principles

1. **System menus, never custom.** Every menu is an `NSMenu`, through SwiftUI `MenuBarExtra(.menu)`, `Menu`, `.contextMenu` or `Picker(.menu)`. macOS 26 draws them in its own Liquid Glass material, with native spacing, separators, shortcut glyphs, submenus, keyboard navigation and VoiceOver. Nothing custom draws a menu, a menu row or a menu background.
2. **Glass is the only surface.** Containers use `glassEffect`. There are no opaque cards and no drawn outlines; edges come from the material's own specular rim.
3. **Bubbly geometry.** Capsules, circles and continuous-corner shapes only. Nested corners are concentric (`ConcentricRectangle`). No sharp corners and no `.cornerRadius()`.
4. **Liquid motion.** Glass shapes merge, split and morph like droplets (`GlassEffectContainer`, `glassEffectID`, `glassEffectUnion`). Interactive glass flexes under the pointer (`.interactive()`). All motion is spring-based.
5. **Legible over anything.** Where `Glass.clear` is used, a dimming layer keeps text at ≥ 4.5:1. Reduce Transparency, Increase Contrast and Reduce Motion each have a defined fallback (section 7).

## 2. Menus (exactly Apple's)

| Where | Component | Contents |
|---|---|---|
| Menu-bar icon | `MenuBarExtra("File Drop Utility", systemImage:) { … }.menuBarExtraStyle(.menu)` | Status line (disabled, SF Symbol), modifier hints (disabled), separator, Settings… ⌘,, Getting Started…, About, separator, Quit ⌘Q. While a job runs, the status line reads "Working · 42%". |
| File rows, Float items, history rows | `.contextMenu { … }` | Open, Show in Finder, Copy, Copy Path, Share ▸ (`ShareLink`), Remove. |
| Choices in Settings and editors (format, preset, terminal app, wheel theme) | `Picker(…).pickerStyle(.menu)` | System pop-up button with a native menu. |
| Overflow actions in a window | `Menu { … } label: { Image(systemName: "ellipsis") }` with `.menuStyle(.button)` and `.buttonStyle(.glass)` | Native pull-down from a round glass button. |
| Share | `ShareLink(items:)` | The system share menu. |

Rules:
- **Order and names** follow the HIG. App-level items (Settings…, About, Quit) use the system names and shortcuts. An ellipsis (…) means the item opens a window. Separators group by task. Disabled items are status, not decoration.
- **Symbols:** SF Symbols, only where Apple's own menus use them (status and destructive items). Text-only otherwise.
- **No custom menu styling:** no custom row heights, backgrounds, tints or animations. On macOS 26 the system's glass menu is the bubbly, reflective look.

## 3. Materials

| Variant | API | Used for |
|---|---|---|
| Regular glass | `.glassEffect(.regular, in: shape)` | Windows' floating panels, cards, toolbars and the Float tabs: anything with body text. |
| Clear glass | `.glassEffect(.clear, in: shape)` with a 20–35% black dimming fill beneath the content | Heads-up surfaces over arbitrary content: the drag wheel's disc, the toast and the editor's floating controls over the image. Most see-through and most water-like. |
| Tinted | `.regular.tint(accent)` or `.clear.tint(accent)` | Prominent actions and the lit wheel petal's glass. |
| Interactive | `.interactive()` on any of the above | Everything the pointer can press: buttons, wheel petals in click mode, Float tabs, tab-bar items. The glass flexes and brightens under the pointer. |
| Identity | `.glassEffect(.identity)` | Turning glass off without changing layout, for example under Reduce Transparency. |

**Buttons:**
- Primary: `.buttonStyle(.glassProminent)` tinted with the blue-teal accent.
- Secondary: `.buttonStyle(.glass)`.

These replace today's hand-made `ProminentGlassButtonStyle` and `SubtleGlassButtonStyle`, so buttons are exactly Apple's.

**Reflective:** Liquid Glass reflects and refracts what's behind it, with a specular rim that responds to the content and the light. No fake highlights, gradients or strokes are painted on top, with one exception: the lit wheel petal's soft sheen (section 5.1).

**Edge-to-edge content:** an image behind the editor's sidebar uses `.backgroundExtensionEffect()`, so it continues under the glass as Apple's apps do.

## 4. Shape and spacing ("bubbly")

| Token | Value | Notes |
|---|---|---|
| Window and panel corners | 28pt continuous | Floating panels sit inset 12pt from the window edge. |
| Cards | 20pt; nested items use `ConcentricRectangle()` | Inner corners always follow the outer ones. |
| Controls | `Capsule` | Buttons, pills, segmented and tab items, chips. |
| Icon buttons | `Circle`, 28–32pt | |
| Wheel | a 252pt disc of rounded petals (13pt corners, 7pt gaps), a recessed centre well and a capsule pill | Already built (`PetalShape`). |
| Spacing scale | 4 · 8 · 12 · 14 · 20 · 28 | One scale everywhere. |
| Depth | contact shadow (r 1.5, y 1) + ambient shadow (r 22, y 12); stronger in dark | Glass floats above content. |

Grouping glass that should feel like one liquid body goes in a `GlassEffectContainer(spacing:)`. When elements come within `spacing` points of each other they visibly merge, like droplets touching:
- the tab bar
- the editor toolbar
- a Float stack's tabs
- the toast and its "Show" button

## 5. Components

### 5.1 Drag wheel (built; keep)

- **Disc:** dark glass plus a black dimming fill; always dark, as a heads-up control. Today it's `.regular` tinted black; it moves to `.clear` with section 8.
- **Petals:** faint white gradient, no outlines.
- **Lit petal:**
  - accent gradient with a soft sheen and an accent glow
  - swells 12pt past the rim, widens 2.5° and leans up to 7pt toward the pointer
  - all on a spring (response 0.3, damping 0.6)
- **Centre well:** inner shadow. Its capsule pill shows the files' size, or the lit petal's name.
- **Opening:** springs from 30% scale with overshoot; labels fade in 90ms later. Closing fades out over 0.14s.
- **Feedback:** a tick plus haptic on each new petal, a pop plus haptic on drop. Both obey the sound and haptics setting.
- **Themes** (new setting): Dark (default), Light (`.clear` with a white dimming fill and dark labels), Accent-tinted.

### 5.2 Main window (Settings…)

- A transparent window whose panels are floating glass: status card, tab bar, content cards.
- **Tab bar:** a `GlassEffectContainer`. The selected capsule moves between tabs with `glassEffectID(_:in:)` and liquid morphs across.
- **Content tabs:** Files, History, Settings, plus Tools in a later phase.
- **Settings controls:** native controls only — `Toggle`, `Picker(.menu)`, `Slider`, `Stepper`, and a modifier-recorder `Button`. They pick up Liquid Glass on their own.

### 5.3 Float tabs (phase 5)

- Glass capsules docked to the left or right screen edge, half-tucked off screen. On hover they slide out (spring) and expand into a vertical stack of thumbnails in one `GlassEffectContainer`, so the stack opens like a droplet splitting.
- **Interactions:**
  - Drag the tab out to carry all files; drag a thumbnail out for one file.
  - Double-click opens the file.
  - The context menu is native (section 2).
- **Paper-clip accent:** an SF Symbol (`paperclip`), not a drawn asset.

### 5.4 Editors (image, video, audio, PDF, collage, frame)

- The content fills the window. The toolbar is a floating glass capsule at the top centre (`GlassEffectContainer`, interactive items). The inspector is a floating glass panel at the trailing edge.
- **Timelines** (video, audio):
  - A glass capsule track holds thumbnails or a waveform.
  - Trim handles and the playhead are interactive glass pills.
  - Ranges (bleep, redaction) are accent-tinted glass capsules that merge when they overlap (`glassEffectUnion`).
- **PDF organizer:** page thumbnails in concentric rounded rects. Dragging reorders with a spring; the dragged page lifts with the ambient shadow.
- **Primary action** ("Save Edited Copy" and the like): `.glassProminent`, bottom-trailing.

### 5.5 Toast and progress

- A capsule of `.clear` glass with dimming, near the top of the screen. It slides down with a spring and morphs into its "Show" button through a `GlassEffectContainer`.
- **Progress:** a thin accent capsule inside the toast. The status menu's first line shows the percentage.

### 5.6 Onboarding

- A transparent window with one floating glass panel. A live click-mode wheel demonstrates each modifier.
- Key caps are small `.regular` glass chips that read from the modifier settings.
- Page changes use the spring transition.

## 6. Colour and type

- **Accent:** blue-teal `accentFill` (light 0/0.36/0.45, dark 0/0.34/0.43).
- **Lit petal gradient:** 0/0.34/0.56 → 0.02/0.60/0.76.
- **Text:** `.primary` plus the tokenised secondary, error and warning colours (all ≥ 4.5:1, measured over a busy backdrop).
- **Type:** SF Pro text styles everywhere. Wheel labels are 8pt bold uppercase with 0.4 tracking, plus 13pt semibold symbols. Numbers use monospaced digits.

## 7. Accessibility fallbacks

| Setting | Behaviour |
|---|---|
| Reduce Transparency | Glass becomes `.identity`, over the window background colour. Clear-glass surfaces use an 85% opaque fill. |
| Increase Contrast | Dimming fills strengthen. High-contrast colour variants. Still no outlines, unless macOS itself adds them to system controls. |
| Reduce Motion | Springs become 0.2s fades. No petal swell or lean, no droplet morphs, no wheel scale-in. |
| VoiceOver | Every petal, tab, Float item and timeline handle has a label, a hint (or its disabled reason) and actions. Menus are native, so they're fully accessible already. |
| Keyboard | Menus are native. Editors support Space (play), ⌫ (delete a mark or range), arrow keys (nudge) and ⌘Z. |

## 8. What changes in the code

1. Replace `ProminentGlassButtonStyle`/`SubtleGlassButtonStyle` with `.glassProminent`/`.glass`.
2. Move HUD surfaces (wheel disc, toast, editor floating controls) to `.clear` glass with dimming.
3. Wrap the tab bar, editor toolbar and toast in `GlassEffectContainer`s, using `glassEffectID` and `glassEffectUnion` where shapes should merge.
4. Use `ConcentricRectangle` for nested corners.
5. Add `.contextMenu` to file, history and Float rows, and `Picker(.menu)` for every choice.
6. Add the wheel theme, and the sound and haptics setting.

Each change is checked with the snapshot sheets (five appearances) and a contrast scan before commit.

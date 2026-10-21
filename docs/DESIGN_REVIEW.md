# Design review: Iris

Reviewed 2026-10-20 against Apple's Human Interface Guidelines (apple-design skill), covering all
44 screens rendered by `FileDropUtility --snapshot` in light, dark and both Increase Contrast
appearances, plus the source. This pass covers the macOS menu-bar app, built with SwiftUI.

### Summary

Rating: **Good.** The app is a quiet macOS utility with one strong idea: the radial wheel that
opens while you drag files. Liquid Glass is used in the right place (floating controls only), and
the brand teal now has three fixed jobs: the primary action, the selection, and success. Its
thesis: *drop files, pick an action on a wheel, get the result without opening another app.* It
will be remembered by the teal-lit wheel petal. This pass fixed one Critical problem (wheel text
below the macOS minimum) and four High ones; what's left is Medium or below.

### Critical (fixed)

- **What:** The drag-and-hold wheel drew its labels at 8 pt bold, and allowed them to shrink to
  6 pt. The centre pill was 9 pt and could shrink to 5.4 pt, so long names such as "Shrink for
  email" were cut off.
  **Why:** `typography.md › Specifications`: macOS default 13 pt, minimum 10 pt. `typography.md ›
  Best practices`: "Keep text truncation to a minimum as font size increases."
  **Fix:** The wheel now opens at 300 pt instead of 252 pt (`WheelGeometry.onScreen`). Labels
  are never smaller than 10 pt (`WheelGeometry.minimumLabelSize`). The centre pill wraps to two
  lines instead of shrinking. (`Wheel/RadialWheel.swift`, `WheelOverlay.swift`,
  `WheelDrop.swift`)

### Improvements

- **High (fixed): the Clear wheel was illegible over bright content.** It had clear glass with
  dark labels and no dimming layer.
  `liquid-glass.md › Review checklist`: "Clear glass appears only over media, with a dark dimming
  layer of about 35% considered when that media is bright."
  Fix: the disc now has a 35% black layer behind the glass, and the Clear wheel draws in its dark
  appearance, so labels are white.
- **High (fixed): some controls could only be clicked with a mouse.** Clip toggles and redaction
  selection in the video editor, bleep selection in the audio editor, and page selection in the
  PDF organiser only worked by clicking.
  `accessibility.md › Mobility`: "verify that your app or game supports these technologies, and
  that your interface elements are appropriately labeled."
  Fix: each control now has the button trait, a selected state and an accessibility action, so
  VoiceOver and Switch Control can operate it.
- **High (fixed): brand colour was spread across many controls.** Applying the teal tint made
  every `.glass` button teal.
  `color.md › Liquid Glass color`: "Refrain from adding color to the background of multiple
  controls." `branding.md › Best practices`: "Apply your app's accent color judiciously."
  Fix: secondary glass buttons, including the redaction Set Start / Set End buttons, and the
  toolbar's More menu carry `.tint(nil)`. Each view has one teal primary button.
- **High (fixed): the app had its own light/dark setting.**
  `dark-mode.md › Best practices`: "Avoid offering an app-specific appearance setting."
  Fix: the setting is removed and the app follows the system.
- **Medium (fixed): Settings wording repeated itself.** The "Format defaults" section had a row
  also called "Format defaults", rows were labelled "Video defaults" and "Audio defaults", and
  "Save to" showed "Next to original" in caption type above a "Next to Original" button.
  Fix: rows are now "Image format", "Video format" and "Audio format". The save location is a
  *Location* row with the buttons Use Original's Folder and Choose Folder… (`writing.md`, judgment).
- **Medium (fixed): Settings was a tab of the main panel, not its own window.**
  `settings.md › macOS`: "When people choose the Settings item in your app's or game's App menu,
  your custom settings window opens."
  Fix: Settings… (⌘,) in the menu-bar menu and the panel's More menu now opens a Settings
  window (`WindowManager.openSettings`, `SettingsWindow`). Minimise and zoom are dimmed, as
  `settings.md` advises. The main window keeps Files and History, and the menu-bar menu has a
  new Open Iris item, so the old Settings… item no longer opens a window that isn't
  Settings.
- **Medium (fixed): the busiest wheels were crowded.** The Tools wheel has 14 petals, and at
  10pt neighbouring labels (Compress / Metadata, QR Code / Collage) nearly touched.
  Fix: drag-and-hold wheels size themselves by petal count
  (`WheelGeometry.diameter(forItemCount:)`): 300pt up to 10 petals, plus 15pt per extra petal,
  up to 360pt. On those busy wheels the labels stay at the 300pt wheel's size, so the extra room
  becomes space between labels. A new `Wheel-ToolsOnScreen` snapshot renders the wheel at the
  size people actually see.
- **Low (fixed): the "Ready" header showed on History and Settings too.** It now shows only on
  Files, next to the drop zone it describes.

### Craft notes

- **Signature:** the teal wheel. Everything around it is deliberately system-plain, which is the
  right call for a utility. Boldness is spent in one place.
- **Teal tokens** (`Design/DesignTokens.swift › Palette`), with contrast measured from hex values:

  | Role | Light | Dark | Increase Contrast | Check |
  |---|---|---|---|---|
  | `teal`: fill behind white text | #0378A8 | #0378A8 | #00578F | white 4.93:1 / 7.61:1 |
  | `tealDeep`: wheel gradient end | #00578F | #00578F | #004470 | white 7.61:1 |
  | `tealInk`: text and symbols | #006B96 | #4CC0E0 | #00578F / #6FD0EA | 5.44:1 on #F5F5F7, 5.36:1 on #3A3A3C |

- **Remove one accessory:** the shortcut line under "Ready" was removed when files are queued,
  because the wheel launchers show the same keys on their own keycaps.

### What works

- Glass appears only on floating layers: toolbar, drop zone, wheel, Floats, toast, tool panels
  and editor bars. Lists and forms use `GroupBox` and grouped `Form`.
- All motion goes through `withMorph`, which falls back to a fade under Reduce Motion.
- The toolbar uses system components: a segmented section picker and a More menu.
- Wording is title case on buttons and menu items, and sentence case on labels and toggles.
- **App icon** (`Resources/AppIcon/`): a centred wheel in teal with one lit petal, no text, and a
  separate dark variant. The lit petal still reads at 16 px. **Menu-bar icon:** a template image
  that turns into a progress ring while a task runs. Both are in line with `app-icons.md` and
  `icons.md`.

### Platform notes

- The `.icns` file can't carry the dark or tinted icon variants. macOS 26 takes those from an
  Icon Composer `.icon` file (`app-icons.md`: "annotate for default, dark, and mono appearance
  variants"). The layers are ready in `Resources/AppIcon/IconComposer-layers/`; building the
  `.icon` needs Xcode, which isn't installed.
- Not checked on screen: Increase Contrast and Reduce Transparency with the real system settings
  on, and Reduce Motion. The snapshot harness can only force appearances, and the window server
  draws glass from the actual system setting.

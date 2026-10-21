# Liquid Glass restyle notes

The app targets macOS 26 only (`Package.swift`: `.macOS(.v26)`), so every Liquid Glass API is
available unconditionally and there is **no fallback path for older systems**. Under Reduce
Transparency and Increase Contrast, the system itself turns `glassEffect`, glass button styles and
toolbars into its solid or high-contrast surfaces; the app no longer branches on those settings
or draws its own substitute.

## Approach

- Glass only on things that float: the toolbar, the drop zone, the wheel, Floats, the toast,
  tool panels, editor tool bars and inspectors. Content uses `GroupBox`, a grouped `Form`, or
  hierarchical system fills (`.quaternary`, `.quinary`), so glass never sits on glass.
- One brand colour, teal, in `DesignTokens.Palette`: `teal` (#0378A8 fills under white text,
  4.9:1), `tealDeep` (#00578F), `tealInk` (text and symbols: #006B96 light, #4CC0E0 dark),
  each with an Increase Contrast value. Every window root calls `brandTint()`, so prominent
  buttons, toggles, sliders and selection are teal. Teal means three things only: the primary
  action (one `.glassProminent` per view, applied through `primaryActionStyle()`), the current
  selection, and success. Prominent buttons fill with `tealDeep`: the system draws their label
  in a light cyan it picks itself, which measured 4.3:1 on `teal` in dark and 6.7:1 on
  `tealDeep`. Secondary
  `.glass` buttons and toolbar items carry `.tint(nil)` so they stay neutral glass.
- Everything else is semantic: `.primary`, `.secondary`, `.red`, `.orange`, hierarchical fills.
  No colour scheme is forced.
- Motion goes through `withMorph`/`morphTransition`, which switch to a fade when Reduce Motion is on.

## Views and APIs

| View | File | APIs |
|---|---|---|
| Shared layer | `Design/GlassStyles.swift` | `glassEffect(Glass.regular.tint().interactive(), in:)` (`glassPanel`), `GroupBox` (`groupBoxed`), `GlassToolPicker` (`GlassEffectContainer`, `glassEffect`, `glassEffectID`), `Keycap` (`glassEffect`) |
| Main window | `Panel/PanelView.swift`, `Windows/WindowManager.swift` | System toolbar via `NSHostingController.sceneBridgingOptions = [.toolbars]`, `.unified` style; segmented `Picker` in `.principal`; `Menu` in `.primaryAction` |
| Files tab | `Panel/FilesTab.swift` | Drop zone `glassPanel(tint:interactive:)`; wheel launchers `.buttonStyle(.glass)` in a `GlassEffectContainer`; lists and result card in `GroupBox` |
| History / Settings | `Panel/HistoryAndSettings.swift` | `GroupBox`; `Form` + `.formStyle(.grouped)`, `LabeledContent` |
| Share button | `Panel/ShareButton.swift` | `NSButton.BezelStyle.glass` |
| Radial wheel | `Wheel/RadialWheel.swift` | Disc `glassEffect(theme.glass, in: Circle())`: Regular → `.regular`, Clear → `.clear`, Tinted → `.regular` over a 60% teal fill; lit petal is teal Liquid Glass (`glassEffect(.regular.tint(teal).interactive())` under a 62% teal gradient layer, #00578F → #0378A8) with the same concentric shape as the other petals, swelling past the rim; petals' glass sits in its own `GlassEffectContainer`; idle petals `.quaternary` |
| Toast | `Wheel/WheelOverlay.swift` | `glassPanel` capsule, borderless text button inside |
| Floats | `Windows/FloatView.swift` | `glassEffect(.regular.interactive())`; collapsed and expanded share `glassEffectID("float", in:)` so opening morphs one shape; rows on `.quinary` |
| Onboarding | `Windows/OnboardingView.swift` | Standard opaque window; `.glassProminent` / `.glass` buttons; cards and mock menu bar on system fills, toggles in `GroupBox` |
| Tool windows | `Windows/ToolWindows.swift` | Floating panel keeps `glassPanel`; inner previews on `.quinary`; swatch selection as a palette `checkmark.circle.fill` |
| Image / video / audio editors | `Editor/*.swift` | `GlassToolPicker` (selected tool tinted, morphs via `glassEffectID`); trim handles `glassEffect(.regular.interactive())`; inspectors and timelines `glassPanel` |
| PDF organizer | `Editor/PDFOrganizer.swift` | Toolbar buttons in one `glassPanel` capsule; page-number badges on `.tint`/`.quaternary` |

## Changes beyond pure styling (behaviour unchanged)

- Wheel theme titles are now Regular, Clear and Tinted; stored raw values are unchanged, so
  saved settings still load.
- The main window's tabs (Files, History) and More menu are in the system toolbar. Settings is a grouped `Form` in its own Settings window.
- The toast's Show button is a text button (glass shouldn't sit on the glass toast).
- Onboarding opens as an opaque standard window instead of a transparent one.
- The wheel keeps the app's original teal. The lit petal is teal-tinted glass with a
  see-through teal layer on it: the wheel's panel is non-activating, and macOS draws glass
  tints on inactive windows without colour, so tint alone turned grey in real use.
- Kept on purpose: media overlays in the editors (crop dimming, the redaction preview's black and
  `.ultraThinMaterial` blur, white playheads with a shadow, the PDF page's white paper and shadow).
  They depict the output or must stay visible over arbitrary media, so they aren't chrome.
- Unrelated fix found during verification: `ToolRunner` could leak a child process if the task
  was cancelled before launch (commit d6978c8).

## Accessibility checks

`FileDropUtility --snapshot <dir>` renders 41 screens in light, dark, light/dark high-contrast
appearance and "dark-largest-text": 205 captures, all produced.

| Check | Status |
|---|---|
| Light / dark | Ran; all 41 screens render with legible system colours. |
| Increase Contrast | Partial. The harness sets the `accessibilityHighContrast*` appearances, but only 5 of 41 screens differ from the normal appearance, because the window server draws glass from the real system setting. A full check needs System Settings › Accessibility › Display › Increase Contrast turned on by hand. |
| Reduce Transparency | Not run: it's a system setting I didn't change. The app has no own branch for it, so it relies on the system's solid fallback. |
| Reduce Motion | Not run, for the same reason; the fade path in `DesignTokens.Motion` is in the code but not checked on screen. |
| Largest Dynamic Type | Ran, with no effect: macOS doesn't apply SwiftUI `dynamicTypeSize`, so text stays at the system size. Text uses text styles throughout, so it follows the macOS text-size settings that do exist. |
| `#Preview` canvas | Not available: only the Command Line Tools are installed (no Xcode). The snapshot harness stands in for it. |
| Contrast notes | White labels on the teal lit petal are about 7.8:1 at the top and 4.9:1 at the bottom of the gradient. On the Tinted wheel the lit petal is the background colour with teal text. Clear wheel labels depend on what's behind the glass, as with any `.clear` glass. |

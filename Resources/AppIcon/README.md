# App icon sources

- `AppIcon.svg` / `AppIcon-Dark.svg`: the 1024 px icon, the radial wheel in the app's teal.
  Light follows the wheel's Tinted theme, dark its Regular theme.
- `HotbarIcon.svg`: the menu bar glyph. The app draws it in code (`Design/AppGlyph.swift`),
  so this file is reference only.
- `IconComposer-layers/`: flat layers (disc, petals, well, lit petal) for Xcode's Icon Composer.
- `src/make_icons.py` writes the SVGs; `src/render.sh` renders them with Chrome and rebuilds
  `AppIcon.icns`. Copy the result to `Resources/AppIcon.icns`, which `scripts/bundle.sh` bundles.

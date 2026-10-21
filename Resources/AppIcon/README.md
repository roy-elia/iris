# Iris app icon sources

- `AppIcon.svg` / `AppIcon-Dark.svg`: the 1024 px icon. Two rings of translucent violet glass
  petals around an eye's iris: gold near the pupil fading to violet, flat radial fibres, a gold
  collarette, a dark limbal rim, a plain pupil and one flat catchlight. Iris the flower and iris
  the eye at once. The shipped `.icns` is the dark version.
- `HotbarIcon.svg`: the menu bar glyph: the petal ring (half opacity) around a solid iris ring and
  pupil. The app draws it in code (`Design/AppGlyph.swift`), so this file is reference only.
- The SVGs come from `../IrisIcon/v3/src/make_v3.py` (variant `6-petal-iris`);
  `../IrisIcon/v3/src/render2.sh` renders PNGs and a preview. Rebuild the iconset from
  `AppIcon-Dark-1024.png` with `iconutil` and copy it to `Resources/AppIcon.icns`, which
  `scripts/bundle.sh` bundles.
- Earlier designs: `../AppIcon-previous/` (the original wheel) and `../IrisIcon/` (all rounds).

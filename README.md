# Iris

A macOS menu-bar utility for files. Drop files on its panel, or hold a modifier key while
dragging, and a wheel of actions opens under the pointer: convert images, video, audio and
documents, compress, resize, strip or edit metadata, build and organize PDFs, trim and redact
video, bleep audio, and share the results.

Requirements: a Mac with Apple silicon running macOS 26 or later.

## Download

1. Download `Iris-<version>.zip` from the latest
   [release](https://github.com/roy-elia/file-drop-utility/releases) and unzip it.
2. Move `Iris.app` to Applications and open it.
3. The app isn't notarized, so the first time macOS says it can't verify it. Open
   **System Settings › Privacy & Security**, scroll to Security and click **Open Anyway**
   next to Iris. You only do this once.

## Build from source

You need Apple's Command Line Tools (`xcode-select --install`); Xcode is optional.

```bash
git clone https://github.com/roy-elia/file-drop-utility.git
cd file-drop-utility
scripts/install.sh --install
```

`scripts/install.sh` checks your Mac, then:

1. runs `scripts/fetch-tools.sh`, which downloads ffmpeg, LAME, libvpx, the AMR codecs,
   cwebp, ExifTool and Monkey's Audio from their official sources, checks each against a
   pinned SHA-256 and builds them (about 5 minutes, once; the output goes in `Vendor/`),
2. runs `scripts/bundle.sh`, which builds `dist/Iris.app` with those helpers inside,
3. with `--install`, copies it to `/Applications` (or `~/Applications`).

Leave out `--install` to only build `dist/Iris.app`. A build made on your own Mac opens
without the Gatekeeper step above.

## Develop

```bash
swift build              # debug build
scripts/test.sh          # swift-testing suite (tool tests skip if Vendor/out is missing)
scripts/lint.sh          # swift-format lint (scripts/lint.sh --fix to reformat)
.build/debug/FileDropUtility --snapshot /tmp/iris-snaps   # render every screen to PNGs
```

`scripts/test.sh` wraps `swift test`. Without Xcode it adds the Command Line Tools'
swift-testing paths, which SwiftPM doesn't find on its own. The snapshot mode needs Screen
Recording permission for the app that runs it.

See [SETUP.md](SETUP.md) for the spec, assumptions and known gaps, and
[GLASS_NOTES.md](GLASS_NOTES.md) for the Liquid Glass design.

## Licence

Iris is released under the [MIT licence](LICENSE). The bundled helpers keep their own
licences (ffmpeg is built LGPL-only); they ship inside the app in
`Iris.app/Contents/Resources/Licenses`.

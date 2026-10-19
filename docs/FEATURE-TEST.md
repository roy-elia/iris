# Feature self-test

2026-10-19, 11:15

**857 passed, 0 failed, 26 correctly refused (nothing to find in that input), 150 skipped (system UI), 289 disabled for the input (with the reason shown).**

| Input | Wheel | Segment | Result | Detail |
|---|---|---|---|---|
| menu | - | Settings… | PASS | window opened, 400×310 |
| menu | - | Getting Started… | PASS | window opened, 820×520 |
| png | Convert | PNG | PASS | scene.png |
| png | Convert | PDF | PASS | scene.pdf |
| png | Convert | JPEG | PASS | scene.jpg |
| png | Convert | HEIC | PASS | scene.heic |
| png | Convert | AVIF | PASS | scene.avif |
| png | Convert | TIFF | PASS | scene.tiff |
| png | Convert | BMP | PASS | scene.bmp |
| png | Convert | WebP | PASS | scene.webp |
| png | Convert | GIF | PASS | scene.gif |
| png | Convert | ICO | PASS | scene.ico |
| png | Convert | ICNS | PASS | scene.icns |
| png | Convert | JP2 | PASS | scene.jp2 |
| png | Convert | TGA | PASS | scene.tga |
| png | Convert | EXR | PASS | scene.exr |
| png | Tools | Compress | PASS | window "Compress"; saved: scene compressed.heic |
| png | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.png |
| png | Tools | Annotate | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Tools | Redact | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Tools | Crop | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.png |
| png | Tools | Frame | PASS | window "Frame"; saved: scene framed.png |
| png | Tools | Collage | off | Two or more images |
| png | Tools | QR Code | refused | scene.png No QR codes found. |
| png | Tools | Resize | PASS | window "Resize"; saved: scene resized.png |
| png | Tools | Grayscale | PASS | scene grayscale.png |
| png | Tools | Adjust | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| png | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| png | Actions | Add to Float | off | No Float is open |
| png | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| png | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| png | Actions | Copy Path | PASS | path text copied |
| png | Actions | Zip | PASS | scene.png.zip |
| png | Actions | Terminal | skip | would open Terminal.app at the folder |
| jpg | Convert | PNG | PASS | scene.png |
| jpg | Convert | PDF | PASS | scene.pdf |
| jpg | Convert | JPEG | PASS | scene.jpg |
| jpg | Convert | HEIC | PASS | scene.heic |
| jpg | Convert | AVIF | PASS | scene.avif |
| jpg | Convert | TIFF | PASS | scene.tiff |
| jpg | Convert | BMP | PASS | scene.bmp |
| jpg | Convert | WebP | PASS | scene.webp |
| jpg | Convert | GIF | PASS | scene.gif |
| jpg | Convert | ICO | PASS | scene.ico |
| jpg | Convert | ICNS | PASS | scene.icns |
| jpg | Convert | JP2 | PASS | scene.jp2 |
| jpg | Convert | TGA | PASS | scene.tga |
| jpg | Convert | EXR | PASS | scene.exr |
| jpg | Tools | Compress | PASS | window "Compress"; saved: scene compressed.jpg |
| jpg | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.jpg |
| jpg | Tools | Annotate | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Tools | Redact | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Tools | Crop | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.jpg |
| jpg | Tools | Frame | PASS | window "Frame"; saved: scene framed.png |
| jpg | Tools | Collage | off | Two or more images |
| jpg | Tools | QR Code | refused | scene.jpg No QR codes found. |
| jpg | Tools | Resize | PASS | window "Resize"; saved: scene resized.jpg |
| jpg | Tools | Grayscale | PASS | scene grayscale.jpg |
| jpg | Tools | Adjust | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| jpg | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| jpg | Actions | Add to Float | off | No Float is open |
| jpg | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| jpg | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| jpg | Actions | Copy Path | PASS | path text copied |
| jpg | Actions | Zip | PASS | scene.jpg.zip |
| jpg | Actions | Terminal | skip | would open Terminal.app at the folder |
| heic | Convert | PNG | PASS | scene.png |
| heic | Convert | PDF | PASS | scene.pdf |
| heic | Convert | JPEG | PASS | scene.jpg |
| heic | Convert | HEIC | PASS | scene.heic |
| heic | Convert | AVIF | PASS | scene.avif |
| heic | Convert | TIFF | PASS | scene.tiff |
| heic | Convert | BMP | PASS | scene.bmp |
| heic | Convert | WebP | PASS | scene.webp |
| heic | Convert | GIF | PASS | scene.gif |
| heic | Convert | ICO | PASS | scene.ico |
| heic | Convert | ICNS | PASS | scene.icns |
| heic | Convert | JP2 | PASS | scene.jp2 |
| heic | Convert | TGA | PASS | scene.tga |
| heic | Convert | EXR | PASS | scene.exr |
| heic | Tools | Compress | PASS | window "Compress"; saved: scene compressed.heic |
| heic | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.heic |
| heic | Tools | Annotate | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Tools | Redact | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Tools | Crop | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.heic |
| heic | Tools | Frame | PASS | window "Frame"; saved: scene framed.png |
| heic | Tools | Collage | off | Two or more images |
| heic | Tools | QR Code | refused | scene.heic No QR codes found. |
| heic | Tools | Resize | PASS | window "Resize"; saved: scene resized.heic |
| heic | Tools | Grayscale | PASS | scene grayscale.heic |
| heic | Tools | Adjust | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| heic | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| heic | Actions | Add to Float | off | No Float is open |
| heic | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| heic | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| heic | Actions | Copy Path | PASS | path text copied |
| heic | Actions | Zip | PASS | scene.heic.zip |
| heic | Actions | Terminal | skip | would open Terminal.app at the folder |
| svg | Convert | PNG | PASS | logo.png |
| svg | Convert | PDF | PASS | logo.pdf |
| svg | Convert | JPEG | PASS | logo.jpg |
| svg | Convert | HEIC | PASS | logo.heic |
| svg | Convert | AVIF | PASS | logo.avif |
| svg | Convert | TIFF | PASS | logo.tiff |
| svg | Convert | BMP | PASS | logo.bmp |
| svg | Convert | WebP | PASS | logo.webp |
| svg | Convert | GIF | PASS | logo.gif |
| svg | Convert | ICO | PASS | logo.ico |
| svg | Convert | ICNS | PASS | logo.icns |
| svg | Convert | JP2 | PASS | logo.jp2 |
| svg | Convert | TGA | PASS | logo.tga |
| svg | Convert | EXR | PASS | logo.exr |
| svg | Tools | Compress | PASS | window "Compress"; saved: logo compressed.heic |
| svg | Tools | Metadata | off | Not for this format |
| svg | Tools | Annotate | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Tools | Redact | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Tools | Crop | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Tools | Add BG | PASS | window "Background"; saved: logo no-bg.png |
| svg | Tools | Frame | PASS | window "Frame"; saved: logo framed.png |
| svg | Tools | Collage | off | Two or more images |
| svg | Tools | QR Code | refused | logo.svg No QR codes found. |
| svg | Tools | Resize | PASS | window "Resize"; saved: logo resized.png |
| svg | Tools | Grayscale | PASS | logo grayscale.png |
| svg | Tools | Adjust | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| svg | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| svg | Actions | Add to Float | off | No Float is open |
| svg | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| svg | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| svg | Actions | Copy Path | PASS | path text copied |
| svg | Actions | Zip | PASS | logo.svg.zip |
| svg | Actions | Terminal | skip | would open Terminal.app at the folder |
| qr | Convert | PNG | PASS | menu-qr.png |
| qr | Convert | PDF | PASS | menu-qr.pdf |
| qr | Convert | JPEG | PASS | menu-qr.jpg |
| qr | Convert | HEIC | PASS | menu-qr.heic |
| qr | Convert | AVIF | PASS | menu-qr.avif |
| qr | Convert | TIFF | PASS | menu-qr.tiff |
| qr | Convert | BMP | PASS | menu-qr.bmp |
| qr | Convert | WebP | PASS | menu-qr.webp |
| qr | Convert | GIF | PASS | menu-qr.gif |
| qr | Convert | ICO | PASS | menu-qr.ico |
| qr | Convert | ICNS | PASS | menu-qr.icns |
| qr | Convert | JP2 | PASS | menu-qr.jp2 |
| qr | Convert | TGA | PASS | menu-qr.tga |
| qr | Convert | EXR | PASS | menu-qr.exr |
| qr | Tools | Compress | PASS | window "Compress"; saved: menu-qr compressed.heic |
| qr | Tools | Metadata | PASS | window "Metadata"; saved: menu-qr metadata.png |
| qr | Tools | Annotate | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Tools | Redact | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Tools | Crop | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Tools | Add BG | refused | window "Background"; saved: menu-qr.png No clear subject was found in menu-qr.png. |
| qr | Tools | Frame | PASS | window "Frame"; saved: menu-qr framed.png |
| qr | Tools | Collage | off | Two or more images |
| qr | Tools | QR Code | PASS | read: https://example.com/menu |
| qr | Tools | Resize | PASS | window "Resize"; saved: menu-qr resized.png |
| qr | Tools | Grayscale | PASS | menu-qr grayscale.png |
| qr | Tools | Adjust | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| qr | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| qr | Actions | Add to Float | off | No Float is open |
| qr | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| qr | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| qr | Actions | Copy Path | PASS | path text copied |
| qr | Actions | Zip | PASS | menu-qr.png.zip |
| qr | Actions | Terminal | skip | would open Terminal.app at the folder |
| psd | Convert | PNG | PASS | layers.png |
| psd | Convert | PDF | PASS | layers.pdf |
| psd | Convert | JPEG | PASS | layers.jpg |
| psd | Convert | HEIC | PASS | layers.heic |
| psd | Convert | AVIF | PASS | layers.avif |
| psd | Convert | TIFF | PASS | layers.tiff |
| psd | Convert | BMP | PASS | layers.bmp |
| psd | Convert | WebP | PASS | layers.webp |
| psd | Convert | GIF | PASS | layers.gif |
| psd | Convert | ICO | PASS | layers.ico |
| psd | Convert | ICNS | PASS | layers.icns |
| psd | Convert | JP2 | PASS | layers.jp2 |
| psd | Convert | TGA | PASS | layers.tga |
| psd | Convert | EXR | PASS | layers.exr |
| psd | Tools | Compress | PASS | window "Compress"; saved: layers compressed.heic |
| psd | Tools | Metadata | PASS | window "Metadata"; saved: layers metadata.psd |
| psd | Tools | Annotate | PASS | window "Edit layers.psd"; saved: layers edited.png |
| psd | Tools | Redact | PASS | window "Edit layers.psd"; saved: layers edited.png |
| psd | Tools | Crop | PASS | window "Edit layers.psd"; saved: layers edited.png |
| psd | Tools | Add BG | PASS | window "Background"; saved: layers no-bg.png |
| psd | Tools | Frame | PASS | window "Frame"; saved: layers framed.png |
| psd | Tools | Collage | off | Two or more images |
| psd | Tools | QR Code | refused | layers.psd No QR codes found. |
| psd | Tools | Resize | PASS | window "Resize"; saved: layers resized.png |
| psd | Tools | Grayscale | PASS | layers grayscale.png |
| psd | Tools | Adjust | PASS | window "Edit layers.psd"; saved: layers edited.png |
| psd | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| psd | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| psd | Actions | Add to Float | off | No Float is open |
| psd | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| psd | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| psd | Actions | Copy Path | PASS | path text copied |
| psd | Actions | Zip | PASS | layers.psd.zip |
| psd | Actions | Terminal | skip | would open Terminal.app at the folder |
| tga | Convert | PNG | PASS | texture.png |
| tga | Convert | PDF | PASS | texture.pdf |
| tga | Convert | JPEG | PASS | texture.jpg |
| tga | Convert | HEIC | PASS | texture.heic |
| tga | Convert | AVIF | PASS | texture.avif |
| tga | Convert | TIFF | PASS | texture.tiff |
| tga | Convert | BMP | PASS | texture.bmp |
| tga | Convert | WebP | PASS | texture.webp |
| tga | Convert | GIF | PASS | texture.gif |
| tga | Convert | ICO | PASS | texture.ico |
| tga | Convert | ICNS | PASS | texture.icns |
| tga | Convert | JP2 | PASS | texture.jp2 |
| tga | Convert | TGA | PASS | texture.tga |
| tga | Convert | EXR | PASS | texture.exr |
| tga | Tools | Compress | PASS | window "Compress"; saved: texture compressed.heic |
| tga | Tools | Metadata | off | Not for this format |
| tga | Tools | Annotate | PASS | window "Edit texture.tga"; saved: texture edited.tga |
| tga | Tools | Redact | PASS | window "Edit texture.tga"; saved: texture edited.tga |
| tga | Tools | Crop | PASS | window "Edit texture.tga"; saved: texture edited.tga |
| tga | Tools | Add BG | PASS | window "Background"; saved: texture no-bg.tga |
| tga | Tools | Frame | PASS | window "Frame"; saved: texture framed.png |
| tga | Tools | Collage | off | Two or more images |
| tga | Tools | QR Code | refused | texture.tga No QR codes found. |
| tga | Tools | Resize | PASS | window "Resize"; saved: texture resized.tga |
| tga | Tools | Grayscale | PASS | texture grayscale.tga |
| tga | Tools | Adjust | PASS | window "Edit texture.tga"; saved: texture edited.tga |
| tga | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| tga | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| tga | Actions | Add to Float | off | No Float is open |
| tga | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| tga | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| tga | Actions | Copy Path | PASS | path text copied |
| tga | Actions | Zip | PASS | texture.tga.zip |
| tga | Actions | Terminal | skip | would open Terminal.app at the folder |
| exr | Convert | PNG | PASS | render.png |
| exr | Convert | PDF | PASS | render.pdf |
| exr | Convert | JPEG | PASS | render.jpg |
| exr | Convert | HEIC | PASS | render.heic |
| exr | Convert | AVIF | PASS | render.avif |
| exr | Convert | TIFF | PASS | render.tiff |
| exr | Convert | BMP | PASS | render.bmp |
| exr | Convert | WebP | PASS | render.webp |
| exr | Convert | GIF | PASS | render.gif |
| exr | Convert | ICO | PASS | render.ico |
| exr | Convert | ICNS | PASS | render.icns |
| exr | Convert | JP2 | PASS | render.jp2 |
| exr | Convert | TGA | PASS | render.tga |
| exr | Convert | EXR | PASS | render.exr |
| exr | Tools | Compress | PASS | window "Compress"; saved: render compressed.heic |
| exr | Tools | Metadata | off | Not for this format |
| exr | Tools | Annotate | PASS | window "Edit render.exr"; saved: render edited.exr |
| exr | Tools | Redact | PASS | window "Edit render.exr"; saved: render edited.exr |
| exr | Tools | Crop | PASS | window "Edit render.exr"; saved: render edited.exr |
| exr | Tools | Add BG | PASS | window "Background"; saved: render no-bg.exr |
| exr | Tools | Frame | PASS | window "Frame"; saved: render framed.png |
| exr | Tools | Collage | off | Two or more images |
| exr | Tools | QR Code | refused | render.exr No QR codes found. |
| exr | Tools | Resize | PASS | window "Resize"; saved: render resized.exr |
| exr | Tools | Grayscale | PASS | render grayscale.exr |
| exr | Tools | Adjust | PASS | window "Edit render.exr"; saved: render edited.exr |
| exr | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| exr | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| exr | Actions | Add to Float | off | No Float is open |
| exr | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| exr | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| exr | Actions | Copy Path | PASS | path text copied |
| exr | Actions | Zip | PASS | render.exr.zip |
| exr | Actions | Terminal | skip | would open Terminal.app at the folder |
| ico | Convert | PNG | PASS | favicon.png |
| ico | Convert | PDF | PASS | favicon.pdf |
| ico | Convert | JPEG | PASS | favicon.jpg |
| ico | Convert | HEIC | PASS | favicon.heic |
| ico | Convert | AVIF | PASS | favicon.avif |
| ico | Convert | TIFF | PASS | favicon.tiff |
| ico | Convert | BMP | PASS | favicon.bmp |
| ico | Convert | WebP | PASS | favicon.webp |
| ico | Convert | GIF | PASS | favicon.gif |
| ico | Convert | ICO | PASS | favicon.ico |
| ico | Convert | ICNS | PASS | favicon.icns |
| ico | Convert | JP2 | PASS | favicon.jp2 |
| ico | Convert | TGA | PASS | favicon.tga |
| ico | Convert | EXR | PASS | favicon.exr |
| ico | Tools | Compress | PASS | window "Compress"; saved: favicon compressed.heic |
| ico | Tools | Metadata | off | Not for this format |
| ico | Tools | Annotate | PASS | window "Edit favicon.ico"; saved: favicon edited.png |
| ico | Tools | Redact | PASS | window "Edit favicon.ico"; saved: favicon edited.png |
| ico | Tools | Crop | PASS | window "Edit favicon.ico"; saved: favicon edited.png |
| ico | Tools | Add BG | PASS | window "Background"; saved: favicon no-bg.png |
| ico | Tools | Frame | PASS | window "Frame"; saved: favicon framed.png |
| ico | Tools | Collage | off | Two or more images |
| ico | Tools | QR Code | refused | favicon.ico No QR codes found. |
| ico | Tools | Resize | PASS | window "Resize"; saved: favicon resized.png |
| ico | Tools | Grayscale | PASS | favicon grayscale.png |
| ico | Tools | Adjust | PASS | window "Edit favicon.ico"; saved: favicon edited.png |
| ico | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| ico | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| ico | Actions | Add to Float | off | No Float is open |
| ico | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| ico | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| ico | Actions | Copy Path | PASS | path text copied |
| ico | Actions | Zip | PASS | favicon.ico.zip |
| ico | Actions | Terminal | skip | would open Terminal.app at the folder |
| hdr | Convert | PNG | PASS | sky.png |
| hdr | Convert | PDF | PASS | sky.pdf |
| hdr | Convert | JPEG | PASS | sky.jpg |
| hdr | Convert | HEIC | PASS | sky.heic |
| hdr | Convert | AVIF | PASS | sky.avif |
| hdr | Convert | TIFF | PASS | sky.tiff |
| hdr | Convert | BMP | PASS | sky.bmp |
| hdr | Convert | WebP | PASS | sky.webp |
| hdr | Convert | GIF | PASS | sky.gif |
| hdr | Convert | ICO | PASS | sky.ico |
| hdr | Convert | ICNS | PASS | sky.icns |
| hdr | Convert | JP2 | PASS | sky.jp2 |
| hdr | Convert | TGA | PASS | sky.tga |
| hdr | Convert | EXR | PASS | sky.exr |
| hdr | Tools | Compress | refused | window "Compress"; saved: sky.hdr sky.hdr is already as small as it gets. |
| hdr | Tools | Metadata | off | Not for this format |
| hdr | Tools | Annotate | PASS | window "Edit sky.hdr"; saved: sky edited.png |
| hdr | Tools | Redact | PASS | window "Edit sky.hdr"; saved: sky edited.png |
| hdr | Tools | Crop | PASS | window "Edit sky.hdr"; saved: sky edited.png |
| hdr | Tools | Add BG | refused | window "Background"; saved: sky.hdr No clear subject was found in sky.hdr. |
| hdr | Tools | Frame | PASS | window "Frame"; saved: sky framed.png |
| hdr | Tools | Collage | off | Two or more images |
| hdr | Tools | QR Code | refused | sky.hdr No QR codes found. |
| hdr | Tools | Resize | PASS | window "Resize"; saved: sky resized.png |
| hdr | Tools | Grayscale | PASS | sky grayscale.png |
| hdr | Tools | Adjust | PASS | window "Edit sky.hdr"; saved: sky edited.png |
| hdr | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| hdr | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| hdr | Actions | Add to Float | off | No Float is open |
| hdr | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| hdr | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| hdr | Actions | Copy Path | PASS | path text copied |
| hdr | Actions | Zip | PASS | sky.hdr.zip |
| hdr | Actions | Terminal | skip | would open Terminal.app at the folder |
| dng | Convert | PNG | PASS | camera.png |
| dng | Convert | PDF | PASS | camera.pdf |
| dng | Convert | JPEG | PASS | camera.jpg |
| dng | Convert | HEIC | PASS | camera.heic |
| dng | Convert | AVIF | PASS | camera.avif |
| dng | Convert | TIFF | PASS | camera.tiff |
| dng | Convert | BMP | PASS | camera.bmp |
| dng | Convert | WebP | PASS | camera.webp |
| dng | Convert | GIF | PASS | camera.gif |
| dng | Convert | ICO | PASS | camera.ico |
| dng | Convert | ICNS | PASS | camera.icns |
| dng | Convert | JP2 | PASS | camera.jp2 |
| dng | Convert | TGA | PASS | camera.tga |
| dng | Convert | EXR | PASS | camera.exr |
| dng | Tools | Compress | PASS | window "Compress"; saved: camera compressed.jpg |
| dng | Tools | Metadata | PASS | window "Metadata"; saved: camera metadata.dng |
| dng | Tools | Annotate | PASS | window "Edit camera.dng"; saved: camera edited.png |
| dng | Tools | Redact | PASS | window "Edit camera.dng"; saved: camera edited.png |
| dng | Tools | Crop | PASS | window "Edit camera.dng"; saved: camera edited.png |
| dng | Tools | Add BG | refused | window "Background"; saved: camera.dng No clear subject was found in camera.dng. |
| dng | Tools | Frame | PASS | window "Frame"; saved: camera framed.png |
| dng | Tools | Collage | off | Two or more images |
| dng | Tools | QR Code | refused | camera.dng No QR codes found. |
| dng | Tools | Resize | PASS | window "Resize"; saved: camera resized.png |
| dng | Tools | Grayscale | PASS | camera grayscale.png |
| dng | Tools | Adjust | PASS | window "Edit camera.dng"; saved: camera edited.png |
| dng | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| dng | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| dng | Actions | Add to Float | off | No Float is open |
| dng | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| dng | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| dng | Actions | Copy Path | PASS | path text copied |
| dng | Actions | Zip | PASS | camera.dng.zip |
| dng | Actions | Terminal | skip | would open Terminal.app at the folder |
| images×2 | Convert | PNG | PASS | scene.png, scene (1).png |
| images×2 | Convert | PDF | PASS | Images.pdf |
| images×2 | Convert | JPEG | PASS | scene.jpg, scene (1).jpg |
| images×2 | Convert | HEIC | PASS | scene.heic, scene (1).heic |
| images×2 | Convert | AVIF | PASS | scene.avif, scene (1).avif |
| images×2 | Convert | TIFF | PASS | scene.tiff, scene (1).tiff |
| images×2 | Convert | BMP | PASS | scene.bmp, scene (1).bmp |
| images×2 | Convert | WebP | PASS | scene.webp, scene (1).webp |
| images×2 | Convert | GIF | PASS | scene.gif, scene (1).gif |
| images×2 | Convert | ICO | PASS | scene.ico, scene (1).ico |
| images×2 | Convert | ICNS | PASS | scene.icns, scene (1).icns |
| images×2 | Convert | JP2 | PASS | scene.jp2, scene (1).jp2 |
| images×2 | Convert | TGA | PASS | scene.tga, scene (1).tga |
| images×2 | Convert | EXR | PASS | scene.exr, scene (1).exr |
| images×2 | Tools | Compress | PASS | window "Compress"; saved: scene compressed.heic, scene compressed.jpg |
| images×2 | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.png, scene metadata.jpg |
| images×2 | Tools | Annotate | off | One image at a time |
| images×2 | Tools | Redact | off | One image at a time |
| images×2 | Tools | Crop | PASS | window "Edit scene.png"; saved: scene edited.png, scene edited.jpg |
| images×2 | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.png, scene no-bg.jpg |
| images×2 | Tools | Frame | PASS | window "Frame"; saved: scene framed.png, scene framed (1).png |
| images×2 | Tools | Collage | PASS | window "Collage"; saved: Collage.png |
| images×2 | Tools | QR Code | refused | scene.png No QR codes found.; scene.jpg No QR codes found. |
| images×2 | Tools | Resize | PASS | window "Resize"; saved: scene resized.png, scene resized.jpg |
| images×2 | Tools | Grayscale | PASS | scene grayscale.png, scene grayscale.jpg |
| images×2 | Tools | Adjust | off | One image at a time |
| images×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| images×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| images×2 | Actions | Add to Float | off | No Float is open |
| images×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| images×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| images×2 | Actions | Copy Path | PASS | path text copied |
| images×2 | Actions | Zip | PASS | Archive.zip |
| images×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| mp4 | Convert | MP4 | PASS | clip.mp4 |
| mp4 | Convert | HEVC | PASS | clip HEVC.mp4 |
| mp4 | Convert | 720p | PASS | clip 720p.mp4 |
| mp4 | Convert | MOV | PASS | clip.mov |
| mp4 | Convert | M4V | PASS | clip.m4v |
| mp4 | Convert | MKV | PASS | clip.mkv |
| mp4 | Convert | AVI | PASS | clip.avi |
| mp4 | Convert | WebM | PASS | clip.webm |
| mp4 | Convert | GIF | PASS | clip.gif |
| mp4 | Convert | MP3 | PASS | clip.mp3 |
| mp4 | Convert | M4A | PASS | clip.m4a |
| mp4 | Tools | Compress | PASS | window "Compress"; saved: clip compressed.mp4 |
| mp4 | Tools | Trim | PASS | window "Edit clip.mp4"; saved: clip edited.mp4 |
| mp4 | Tools | Split | PASS | window "Edit clip.mp4"; saved: clip part 1.mp4, clip part 2.mp4 |
| mp4 | Tools | Join | off | Two or more videos |
| mp4 | Tools | Speed | PASS | window "Edit clip.mp4"; saved: clip edited.mp4 |
| mp4 | Tools | Frames | PASS | window "Edit clip.mp4"; saved: clip 0m00.5s.png, clip 0m01.2s.png |
| mp4 | Tools | Crop | PASS | window "Edit clip.mp4"; saved: clip edited.mp4 |
| mp4 | Tools | Redact | PASS | window "Edit clip.mp4"; saved: clip edited.mp4 |
| mp4 | Tools | Subtitles | refused | clip.mp4 clip.mp4 has no subtitle tracks. |
| mp4 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| mp4 | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| mp4 | Actions | Add to Float | off | No Float is open |
| mp4 | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| mp4 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| mp4 | Actions | Copy Path | PASS | path text copied |
| mp4 | Actions | Zip | PASS | clip.mp4.zip |
| mp4 | Actions | Terminal | skip | would open Terminal.app at the folder |
| videos×2 | Convert | MP4 | PASS | clip.mp4, intro.mp4 |
| videos×2 | Convert | HEVC | PASS | clip HEVC.mp4, intro HEVC.mp4 |
| videos×2 | Convert | 720p | PASS | clip 720p.mp4, intro 720p.mp4 |
| videos×2 | Convert | MOV | PASS | clip.mov, intro.mov |
| videos×2 | Convert | M4V | PASS | clip.m4v, intro.m4v |
| videos×2 | Convert | MKV | PASS | clip.mkv, intro.mkv |
| videos×2 | Convert | AVI | PASS | clip.avi, intro.avi |
| videos×2 | Convert | WebM | PASS | clip.webm, intro.webm |
| videos×2 | Convert | GIF | PASS | clip.gif, intro.gif |
| videos×2 | Convert | MP3 | PASS | clip.mp3, intro.mp3 |
| videos×2 | Convert | M4A | PASS | clip.m4a, intro.m4a |
| videos×2 | Tools | Compress | PASS | window "Compress"; saved: clip compressed.mp4, intro compressed.mov |
| videos×2 | Tools | Trim | off | One video at a time |
| videos×2 | Tools | Split | off | One video at a time |
| videos×2 | Tools | Join | PASS | window "Join Videos"; saved: Joined.mp4 |
| videos×2 | Tools | Speed | off | One video at a time |
| videos×2 | Tools | Frames | off | One video at a time |
| videos×2 | Tools | Crop | off | One video at a time |
| videos×2 | Tools | Redact | off | One video at a time |
| videos×2 | Tools | Subtitles | refused | clip.mp4 clip.mp4 has no subtitle tracks.; intro.mov intro.mov has no subtitle tracks. |
| videos×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| videos×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| videos×2 | Actions | Add to Float | off | No Float is open |
| videos×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| videos×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| videos×2 | Actions | Copy Path | PASS | path text copied |
| videos×2 | Actions | Zip | PASS | Archive.zip |
| videos×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| subbed.mkv | Convert | MP4 | PASS | subbed.mp4 |
| subbed.mkv | Convert | HEVC | PASS | subbed HEVC.mp4 |
| subbed.mkv | Convert | 720p | PASS | subbed 720p.mp4 |
| subbed.mkv | Convert | MOV | PASS | subbed.mov |
| subbed.mkv | Convert | M4V | PASS | subbed.m4v |
| subbed.mkv | Convert | MKV | PASS | subbed.mkv |
| subbed.mkv | Convert | AVI | PASS | subbed.avi |
| subbed.mkv | Convert | WebM | PASS | subbed.webm |
| subbed.mkv | Convert | GIF | PASS | subbed.gif |
| subbed.mkv | Convert | MP3 | PASS | subbed.mp3 |
| subbed.mkv | Convert | M4A | PASS | subbed.m4a |
| subbed.mkv | Tools | Compress | PASS | window "Compress"; saved: subbed compressed.mkv |
| subbed.mkv | Tools | Trim | PASS | window "Edit subbed.mkv"; saved: subbed edited.mkv |
| subbed.mkv | Tools | Split | PASS | window "Edit subbed.mkv"; saved: subbed part 1.mkv, subbed part 2.mkv |
| subbed.mkv | Tools | Join | off | Two or more videos |
| subbed.mkv | Tools | Speed | PASS | window "Edit subbed.mkv"; saved: subbed edited.mkv |
| subbed.mkv | Tools | Frames | PASS | window "Edit subbed.mkv"; saved: subbed 0m00.5s.png, subbed 0m01.2s.png |
| subbed.mkv | Tools | Crop | PASS | window "Edit subbed.mkv"; saved: subbed edited.mkv |
| subbed.mkv | Tools | Redact | PASS | window "Edit subbed.mkv"; saved: subbed edited.mkv |
| subbed.mkv | Tools | Subtitles | PASS | subbed.srt |
| subbed.mkv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| subbed.mkv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| subbed.mkv | Actions | Add to Float | off | No Float is open |
| subbed.mkv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| subbed.mkv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| subbed.mkv | Actions | Copy Path | PASS | path text copied |
| subbed.mkv | Actions | Zip | PASS | subbed.mkv.zip |
| subbed.mkv | Actions | Terminal | skip | would open Terminal.app at the folder |
| wav | Convert | MP3 | PASS | voice.mp3 |
| wav | Convert | WAV | PASS | voice.wav |
| wav | Convert | M4A | PASS | voice.m4a |
| wav | Convert | AAC | PASS | voice.aac |
| wav | Convert | FLAC | PASS | voice.flac |
| wav | Convert | AIFF | PASS | voice.aiff |
| wav | Convert | OGG | PASS | voice.ogg |
| wav | Convert | Opus | PASS | voice.opus |
| wav | Convert | AMR | PASS | voice.amr |
| wav | Convert | AMR-WB | PASS | voice.awb |
| wav | Convert | APE | PASS | voice.ape |
| wav | Tools | Trim | PASS | window "Edit voice.wav"; saved: voice edited.wav |
| wav | Tools | Bleep | PASS | window "Edit voice.wav"; saved: voice edited.wav |
| wav | Tools | Volume | PASS | window "Edit voice.wav"; saved: voice edited.wav |
| wav | Tools | Channels | PASS | window "Edit voice.wav"; saved: voice edited.wav |
| wav | Tools | Visualizer | PASS | window "Visualizer"; saved: voice visualizer.mp4 |
| wav | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| wav | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| wav | Actions | Add to Float | off | No Float is open |
| wav | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| wav | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| wav | Actions | Copy Path | PASS | path text copied |
| wav | Actions | Zip | PASS | voice.wav.zip |
| wav | Actions | Terminal | skip | would open Terminal.app at the folder |
| audio×2 | Convert | MP3 | PASS | voice.mp3, song.mp3 |
| audio×2 | Convert | WAV | PASS | voice.wav, song.wav |
| audio×2 | Convert | M4A | PASS | voice.m4a, song.m4a |
| audio×2 | Convert | AAC | PASS | voice.aac, song.aac |
| audio×2 | Convert | FLAC | PASS | voice.flac, song.flac |
| audio×2 | Convert | AIFF | PASS | voice.aiff, song.aiff |
| audio×2 | Convert | OGG | PASS | voice.ogg, song.ogg |
| audio×2 | Convert | Opus | PASS | voice.opus, song.opus |
| audio×2 | Convert | AMR | PASS | voice.amr, song.amr |
| audio×2 | Convert | AMR-WB | PASS | voice.awb, song.awb |
| audio×2 | Convert | APE | PASS | voice.ape, song.ape |
| audio×2 | Tools | Trim | off | One file at a time |
| audio×2 | Tools | Bleep | off | One file at a time |
| audio×2 | Tools | Volume | off | One file at a time |
| audio×2 | Tools | Channels | off | One file at a time |
| audio×2 | Tools | Visualizer | PASS | window "Visualizer"; saved: voice visualizer.mp4, song visualizer.mp4 |
| audio×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| audio×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| audio×2 | Actions | Add to Float | off | No Float is open |
| audio×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| audio×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| audio×2 | Actions | Copy Path | PASS | path text copied |
| audio×2 | Actions | Zip | PASS | Archive.zip |
| audio×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| ac3 | Convert | MP3 | PASS | surround.mp3 |
| ac3 | Convert | WAV | PASS | surround.wav |
| ac3 | Convert | M4A | PASS | surround.m4a |
| ac3 | Convert | AAC | PASS | surround.aac |
| ac3 | Convert | FLAC | PASS | surround.flac |
| ac3 | Convert | AIFF | PASS | surround.aiff |
| ac3 | Convert | OGG | PASS | surround.ogg |
| ac3 | Convert | Opus | PASS | surround.opus |
| ac3 | Convert | AMR | PASS | surround.amr |
| ac3 | Convert | AMR-WB | PASS | surround.awb |
| ac3 | Convert | APE | PASS | surround.ape |
| ac3 | Tools | Trim | PASS | window "Edit surround.ac3"; saved: surround edited.m4a |
| ac3 | Tools | Bleep | PASS | window "Edit surround.ac3"; saved: surround edited.m4a |
| ac3 | Tools | Volume | PASS | window "Edit surround.ac3"; saved: surround edited.m4a |
| ac3 | Tools | Channels | PASS | window "Edit surround.ac3"; saved: surround edited.m4a |
| ac3 | Tools | Visualizer | PASS | window "Visualizer"; saved: surround visualizer.mp4 |
| ac3 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| ac3 | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| ac3 | Actions | Add to Float | off | No Float is open |
| ac3 | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| ac3 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| ac3 | Actions | Copy Path | PASS | path text copied |
| ac3 | Actions | Zip | PASS | surround.ac3.zip |
| ac3 | Actions | Terminal | skip | would open Terminal.app at the folder |
| amr | Convert | MP3 | PASS | memo.mp3 |
| amr | Convert | WAV | PASS | memo.wav |
| amr | Convert | M4A | PASS | memo.m4a |
| amr | Convert | AAC | PASS | memo.aac |
| amr | Convert | FLAC | PASS | memo.flac |
| amr | Convert | AIFF | PASS | memo.aiff |
| amr | Convert | OGG | PASS | memo.ogg |
| amr | Convert | Opus | PASS | memo.opus |
| amr | Convert | AMR | PASS | memo.amr |
| amr | Convert | AMR-WB | PASS | memo.awb |
| amr | Convert | APE | PASS | memo.ape |
| amr | Tools | Trim | PASS | window "Edit memo.amr"; saved: memo edited.amr |
| amr | Tools | Bleep | PASS | window "Edit memo.amr"; saved: memo edited.amr |
| amr | Tools | Volume | PASS | window "Edit memo.amr"; saved: memo edited.amr |
| amr | Tools | Channels | PASS | window "Edit memo.amr"; saved: memo edited.amr |
| amr | Tools | Visualizer | PASS | window "Visualizer"; saved: memo visualizer.mp4 |
| amr | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| amr | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| amr | Actions | Add to Float | off | No Float is open |
| amr | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| amr | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| amr | Actions | Copy Path | PASS | path text copied |
| amr | Actions | Zip | PASS | memo.amr.zip |
| amr | Actions | Terminal | skip | would open Terminal.app at the folder |
| ape | Convert | MP3 | PASS | album.mp3 |
| ape | Convert | WAV | PASS | album.wav |
| ape | Convert | M4A | PASS | album.m4a |
| ape | Convert | AAC | PASS | album.aac |
| ape | Convert | FLAC | PASS | album.flac |
| ape | Convert | AIFF | PASS | album.aiff |
| ape | Convert | OGG | PASS | album.ogg |
| ape | Convert | Opus | PASS | album.opus |
| ape | Convert | AMR | PASS | album.amr |
| ape | Convert | AMR-WB | PASS | album.awb |
| ape | Convert | APE | PASS | album.ape |
| ape | Tools | Trim | PASS | window "Edit album.ape"; saved: album edited.ape |
| ape | Tools | Bleep | PASS | window "Edit album.ape"; saved: album edited.ape |
| ape | Tools | Volume | PASS | window "Edit album.ape"; saved: album edited.ape |
| ape | Tools | Channels | PASS | window "Edit album.ape"; saved: album edited.ape |
| ape | Tools | Visualizer | PASS | window "Visualizer"; saved: album visualizer.mp4 |
| ape | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| ape | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| ape | Actions | Add to Float | off | No Float is open |
| ape | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| ape | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| ape | Actions | Copy Path | PASS | path text copied |
| ape | Actions | Zip | PASS | album.ape.zip |
| ape | Actions | Terminal | skip | would open Terminal.app at the folder |
| pdf | Convert | PNG | PASS | deck page 1.png, deck page 2.png, deck page 3.png +1 |
| pdf | Convert | JPEG | PASS | deck page 1.jpg, deck page 2.jpg, deck page 3.jpg +1 |
| pdf | Convert | TIFF | PASS | deck.tiff |
| pdf | Convert | CBZ | PASS | deck.cbz |
| pdf | Convert | DOCX | PASS | deck.docx |
| pdf | Convert | RTF | PASS | deck.rtf |
| pdf | Convert | Text | PASS | deck.txt |
| pdf | Convert | Markdown | PASS | deck.md |
| pdf | Convert | HTML | PASS | deck.html |
| pdf | Convert | EPUB | PASS | deck.epub |
| pdf | Convert | EPUB Pages | PASS | deck.epub |
| pdf | Tools | Organize | PASS | window "Organize deck.pdf"; saved: deck organized.pdf |
| pdf | Tools | Split | PASS | window "Split PDF"; saved: deck page 1.pdf, deck pages 2-4.pdf |
| pdf | Tools | Compress | PASS | window "Compress"; saved: deck compressed.pdf |
| pdf | Tools | Merge | off | Two or more PDFs |
| pdf | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| pdf | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| pdf | Actions | Add to Float | off | No Float is open |
| pdf | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| pdf | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| pdf | Actions | Copy Path | PASS | path text copied |
| pdf | Actions | Zip | PASS | deck.pdf.zip |
| pdf | Actions | Terminal | skip | would open Terminal.app at the folder |
| pdfs×2 | Convert | PNG | PASS | deck page 1.png, deck page 2.png, deck page 3.png +3 |
| pdfs×2 | Convert | JPEG | PASS | deck page 1.jpg, deck page 2.jpg, deck page 3.jpg +3 |
| pdfs×2 | Convert | TIFF | PASS | deck.tiff, appendix.tiff |
| pdfs×2 | Convert | CBZ | PASS | deck.cbz, appendix.cbz |
| pdfs×2 | Convert | DOCX | PASS | deck.docx, appendix.docx |
| pdfs×2 | Convert | RTF | PASS | deck.rtf, appendix.rtf |
| pdfs×2 | Convert | Text | PASS | deck.txt, appendix.txt |
| pdfs×2 | Convert | Markdown | PASS | deck.md, appendix.md |
| pdfs×2 | Convert | HTML | PASS | deck.html, appendix.html |
| pdfs×2 | Convert | EPUB | PASS | deck.epub, appendix.epub |
| pdfs×2 | Convert | EPUB Pages | PASS | deck.epub, appendix.epub |
| pdfs×2 | Tools | Organize | off | One PDF at a time |
| pdfs×2 | Tools | Split | PASS | window "Split PDF"; saved: deck page 1.pdf, deck pages 2-4.pdf, appendix page 1.pdf +1 |
| pdfs×2 | Tools | Compress | refused | window "Compress"; saved: appendix.pdf appendix.pdf is already as small as it gets. |
| pdfs×2 | Tools | Merge | PASS | Merged.pdf |
| pdfs×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| pdfs×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| pdfs×2 | Actions | Add to Float | off | No Float is open |
| pdfs×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| pdfs×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| pdfs×2 | Actions | Copy Path | PASS | path text copied |
| pdfs×2 | Actions | Zip | PASS | Archive.zip |
| pdfs×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| docx | Convert | PDF | PASS | report.pdf |
| docx | Convert | DOCX | PASS | report.docx |
| docx | Convert | RTF | PASS | report.rtf |
| docx | Convert | Text | PASS | report.txt |
| docx | Convert | Markdown | PASS | report.md |
| docx | Convert | HTML | PASS | report.html |
| docx | Convert | EPUB | PASS | report.epub |
| docx | Convert | Pages | off | Needs Pages |
| docx | Tools | Compress | off | Images and PDFs only |
| docx | Tools | Metadata | off | Images only |
| docx | Tools | Annotate | off | One image at a time |
| docx | Tools | Redact | off | One image at a time |
| docx | Tools | Crop | off | Images only |
| docx | Tools | Add BG | off | Images only |
| docx | Tools | Frame | off | Images only |
| docx | Tools | Collage | off | Two or more images |
| docx | Tools | QR Code | off | Images only |
| docx | Tools | Resize | off | Images only |
| docx | Tools | Grayscale | off | Images only |
| docx | Tools | Adjust | off | One image at a time |
| docx | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| docx | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| docx | Actions | Add to Float | off | No Float is open |
| docx | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| docx | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| docx | Actions | Copy Path | PASS | path text copied |
| docx | Actions | Zip | PASS | report.docx.zip |
| docx | Actions | Terminal | skip | would open Terminal.app at the folder |
| rtf | Convert | PDF | PASS | memo.pdf |
| rtf | Convert | DOCX | PASS | memo.docx |
| rtf | Convert | RTF | PASS | memo.rtf |
| rtf | Convert | Text | PASS | memo.txt |
| rtf | Convert | Markdown | PASS | memo.md |
| rtf | Convert | HTML | PASS | memo.html |
| rtf | Convert | EPUB | PASS | memo.epub |
| rtf | Convert | Pages | off | Needs Pages |
| rtf | Tools | Compress | off | Images and PDFs only |
| rtf | Tools | Metadata | off | Images only |
| rtf | Tools | Annotate | off | One image at a time |
| rtf | Tools | Redact | off | One image at a time |
| rtf | Tools | Crop | off | Images only |
| rtf | Tools | Add BG | off | Images only |
| rtf | Tools | Frame | off | Images only |
| rtf | Tools | Collage | off | Two or more images |
| rtf | Tools | QR Code | off | Images only |
| rtf | Tools | Resize | off | Images only |
| rtf | Tools | Grayscale | off | Images only |
| rtf | Tools | Adjust | off | One image at a time |
| rtf | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| rtf | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| rtf | Actions | Add to Float | off | No Float is open |
| rtf | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| rtf | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| rtf | Actions | Copy Path | PASS | path text copied |
| rtf | Actions | Zip | PASS | memo.rtf.zip |
| rtf | Actions | Terminal | skip | would open Terminal.app at the folder |
| md | Convert | PDF | PASS | notes.pdf |
| md | Convert | DOCX | PASS | notes.docx |
| md | Convert | RTF | PASS | notes.rtf |
| md | Convert | Text | PASS | notes.txt |
| md | Convert | Markdown | PASS | notes.md |
| md | Convert | HTML | PASS | notes.html |
| md | Convert | EPUB | PASS | notes.epub |
| md | Convert | Pages | off | Needs Pages |
| md | Tools | Compress | off | Images and PDFs only |
| md | Tools | Metadata | off | Images only |
| md | Tools | Annotate | off | One image at a time |
| md | Tools | Redact | off | One image at a time |
| md | Tools | Crop | off | Images only |
| md | Tools | Add BG | off | Images only |
| md | Tools | Frame | off | Images only |
| md | Tools | Collage | off | Two or more images |
| md | Tools | QR Code | off | Images only |
| md | Tools | Resize | off | Images only |
| md | Tools | Grayscale | off | Images only |
| md | Tools | Adjust | off | One image at a time |
| md | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| md | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| md | Actions | Add to Float | off | No Float is open |
| md | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| md | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| md | Actions | Copy Path | PASS | path text copied |
| md | Actions | Zip | PASS | notes.md.zip |
| md | Actions | Terminal | skip | would open Terminal.app at the folder |
| html | Convert | PDF | PASS | page.pdf |
| html | Convert | DOCX | PASS | page.docx |
| html | Convert | RTF | PASS | page.rtf |
| html | Convert | Text | PASS | page.txt |
| html | Convert | Markdown | PASS | page.md |
| html | Convert | HTML | PASS | page.html |
| html | Convert | EPUB | PASS | page.epub |
| html | Convert | Pages | off | Needs Pages |
| html | Tools | Compress | off | Images and PDFs only |
| html | Tools | Metadata | off | Images only |
| html | Tools | Annotate | off | One image at a time |
| html | Tools | Redact | off | One image at a time |
| html | Tools | Crop | off | Images only |
| html | Tools | Add BG | off | Images only |
| html | Tools | Frame | off | Images only |
| html | Tools | Collage | off | Two or more images |
| html | Tools | QR Code | off | Images only |
| html | Tools | Resize | off | Images only |
| html | Tools | Grayscale | off | Images only |
| html | Tools | Adjust | off | One image at a time |
| html | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| html | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| html | Actions | Add to Float | off | No Float is open |
| html | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| html | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| html | Actions | Copy Path | PASS | path text copied |
| html | Actions | Zip | PASS | page.html.zip |
| html | Actions | Terminal | skip | would open Terminal.app at the folder |
| csv | Convert | PDF | PASS | scores.pdf |
| csv | Convert | DOCX | PASS | scores.docx |
| csv | Convert | RTF | PASS | scores.rtf |
| csv | Convert | Text | PASS | scores.txt |
| csv | Convert | Markdown | PASS | scores.md |
| csv | Convert | HTML | PASS | scores.html |
| csv | Convert | EPUB | PASS | scores.epub |
| csv | Convert | Pages | off | Needs Pages |
| csv | Convert | JSON | PASS | scores.json |
| csv | Convert | vCard | PASS | scores.vcf |
| csv | Tools | Compress | off | Images and PDFs only |
| csv | Tools | Metadata | off | Images only |
| csv | Tools | Annotate | off | One image at a time |
| csv | Tools | Redact | off | One image at a time |
| csv | Tools | Crop | off | Images only |
| csv | Tools | Add BG | off | Images only |
| csv | Tools | Frame | off | Images only |
| csv | Tools | Collage | off | Two or more images |
| csv | Tools | QR Code | off | Images only |
| csv | Tools | Resize | off | Images only |
| csv | Tools | Grayscale | off | Images only |
| csv | Tools | Adjust | off | One image at a time |
| csv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| csv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| csv | Actions | Add to Float | off | No Float is open |
| csv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| csv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| csv | Actions | Copy Path | PASS | path text copied |
| csv | Actions | Zip | PASS | scores.csv.zip |
| csv | Actions | Terminal | skip | would open Terminal.app at the folder |
| contacts.csv | Convert | PDF | PASS | contacts.pdf |
| contacts.csv | Convert | DOCX | PASS | contacts.docx |
| contacts.csv | Convert | RTF | PASS | contacts.rtf |
| contacts.csv | Convert | Text | PASS | contacts.txt |
| contacts.csv | Convert | Markdown | PASS | contacts.md |
| contacts.csv | Convert | HTML | PASS | contacts.html |
| contacts.csv | Convert | EPUB | PASS | contacts.epub |
| contacts.csv | Convert | Pages | off | Needs Pages |
| contacts.csv | Convert | JSON | PASS | contacts.json |
| contacts.csv | Convert | vCard | PASS | contacts.vcf |
| contacts.csv | Tools | Compress | off | Images and PDFs only |
| contacts.csv | Tools | Metadata | off | Images only |
| contacts.csv | Tools | Annotate | off | One image at a time |
| contacts.csv | Tools | Redact | off | One image at a time |
| contacts.csv | Tools | Crop | off | Images only |
| contacts.csv | Tools | Add BG | off | Images only |
| contacts.csv | Tools | Frame | off | Images only |
| contacts.csv | Tools | Collage | off | Two or more images |
| contacts.csv | Tools | QR Code | off | Images only |
| contacts.csv | Tools | Resize | off | Images only |
| contacts.csv | Tools | Grayscale | off | Images only |
| contacts.csv | Tools | Adjust | off | One image at a time |
| contacts.csv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| contacts.csv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| contacts.csv | Actions | Add to Float | off | No Float is open |
| contacts.csv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| contacts.csv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| contacts.csv | Actions | Copy Path | PASS | path text copied |
| contacts.csv | Actions | Zip | PASS | contacts.csv.zip |
| contacts.csv | Actions | Terminal | skip | would open Terminal.app at the folder |
| json | Convert | CSV | PASS | people.csv |
| json | Convert | XML | PASS | people.xml |
| json | Convert | Plist | PASS | people.plist |
| json | Tools | Compress | off | Images and PDFs only |
| json | Tools | Metadata | off | Images only |
| json | Tools | Annotate | off | One image at a time |
| json | Tools | Redact | off | One image at a time |
| json | Tools | Crop | off | Images only |
| json | Tools | Add BG | off | Images only |
| json | Tools | Frame | off | Images only |
| json | Tools | Collage | off | Two or more images |
| json | Tools | QR Code | off | Images only |
| json | Tools | Resize | off | Images only |
| json | Tools | Grayscale | off | Images only |
| json | Tools | Adjust | off | One image at a time |
| json | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| json | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| json | Actions | Add to Float | off | No Float is open |
| json | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| json | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| json | Actions | Copy Path | PASS | path text copied |
| json | Actions | Zip | PASS | people.json.zip |
| json | Actions | Terminal | skip | would open Terminal.app at the folder |
| xml | Convert | JSON | PASS | catalog.json |
| xml | Tools | Compress | off | Images and PDFs only |
| xml | Tools | Metadata | off | Images only |
| xml | Tools | Annotate | off | One image at a time |
| xml | Tools | Redact | off | One image at a time |
| xml | Tools | Crop | off | Images only |
| xml | Tools | Add BG | off | Images only |
| xml | Tools | Frame | off | Images only |
| xml | Tools | Collage | off | Two or more images |
| xml | Tools | QR Code | off | Images only |
| xml | Tools | Resize | off | Images only |
| xml | Tools | Grayscale | off | Images only |
| xml | Tools | Adjust | off | One image at a time |
| xml | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| xml | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| xml | Actions | Add to Float | off | No Float is open |
| xml | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| xml | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| xml | Actions | Copy Path | PASS | path text copied |
| xml | Actions | Zip | PASS | catalog.xml.zip |
| xml | Actions | Terminal | skip | would open Terminal.app at the folder |
| plist | Convert | JSON | PASS | settings.json |
| plist | Tools | Compress | off | Images and PDFs only |
| plist | Tools | Metadata | off | Images only |
| plist | Tools | Annotate | off | One image at a time |
| plist | Tools | Redact | off | One image at a time |
| plist | Tools | Crop | off | Images only |
| plist | Tools | Add BG | off | Images only |
| plist | Tools | Frame | off | Images only |
| plist | Tools | Collage | off | Two or more images |
| plist | Tools | QR Code | off | Images only |
| plist | Tools | Resize | off | Images only |
| plist | Tools | Grayscale | off | Images only |
| plist | Tools | Adjust | off | One image at a time |
| plist | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| plist | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| plist | Actions | Add to Float | off | No Float is open |
| plist | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| plist | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| plist | Actions | Copy Path | PASS | path text copied |
| plist | Actions | Zip | PASS | settings.plist.zip |
| plist | Actions | Terminal | skip | would open Terminal.app at the folder |
| vcf | Convert | CSV | PASS | contacts.csv |
| vcf | Tools | Compress | off | Images and PDFs only |
| vcf | Tools | Metadata | off | Images only |
| vcf | Tools | Annotate | off | One image at a time |
| vcf | Tools | Redact | off | One image at a time |
| vcf | Tools | Crop | off | Images only |
| vcf | Tools | Add BG | off | Images only |
| vcf | Tools | Frame | off | Images only |
| vcf | Tools | Collage | off | Two or more images |
| vcf | Tools | QR Code | off | Images only |
| vcf | Tools | Resize | off | Images only |
| vcf | Tools | Grayscale | off | Images only |
| vcf | Tools | Adjust | off | One image at a time |
| vcf | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| vcf | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| vcf | Actions | Add to Float | off | No Float is open |
| vcf | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| vcf | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| vcf | Actions | Copy Path | PASS | path text copied |
| vcf | Actions | Zip | PASS | contacts.vcf.zip |
| vcf | Actions | Terminal | skip | would open Terminal.app at the folder |
| clipping | Convert | PDF | PASS | snippet.pdf |
| clipping | Convert | DOCX | PASS | snippet.docx |
| clipping | Convert | RTF | PASS | snippet.rtf |
| clipping | Convert | Text | PASS | snippet.txt |
| clipping | Convert | Markdown | PASS | snippet.md |
| clipping | Convert | HTML | PASS | snippet.html |
| clipping | Convert | EPUB | PASS | snippet.epub |
| clipping | Convert | Pages | off | Needs Pages |
| clipping | Tools | Compress | off | Images and PDFs only |
| clipping | Tools | Metadata | off | Images only |
| clipping | Tools | Annotate | off | One image at a time |
| clipping | Tools | Redact | off | One image at a time |
| clipping | Tools | Crop | off | Images only |
| clipping | Tools | Add BG | off | Images only |
| clipping | Tools | Frame | off | Images only |
| clipping | Tools | Collage | off | Two or more images |
| clipping | Tools | QR Code | off | Images only |
| clipping | Tools | Resize | off | Images only |
| clipping | Tools | Grayscale | off | Images only |
| clipping | Tools | Adjust | off | One image at a time |
| clipping | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| clipping | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| clipping | Actions | Add to Float | off | No Float is open |
| clipping | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| clipping | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| clipping | Actions | Copy Path | PASS | path text copied |
| clipping | Actions | Zip | PASS | snippet.textClipping.zip |
| clipping | Actions | Terminal | skip | would open Terminal.app at the folder |
| srt | Convert | SRT | PASS | film.srt |
| srt | Convert | VTT | PASS | film.vtt |
| srt | Convert | ASS | PASS | film.ass |
| srt | Convert | SSA | PASS | film.ssa |
| srt | Convert | SAMI | PASS | film.smi |
| srt | Convert | LRC | PASS | film.lrc |
| srt | Tools | Compress | off | Images and PDFs only |
| srt | Tools | Metadata | off | Images only |
| srt | Tools | Annotate | off | One image at a time |
| srt | Tools | Redact | off | One image at a time |
| srt | Tools | Crop | off | Images only |
| srt | Tools | Add BG | off | Images only |
| srt | Tools | Frame | off | Images only |
| srt | Tools | Collage | off | Two or more images |
| srt | Tools | QR Code | off | Images only |
| srt | Tools | Resize | off | Images only |
| srt | Tools | Grayscale | off | Images only |
| srt | Tools | Adjust | off | One image at a time |
| srt | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| srt | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| srt | Actions | Add to Float | off | No Float is open |
| srt | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| srt | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| srt | Actions | Copy Path | PASS | path text copied |
| srt | Actions | Zip | PASS | film.srt.zip |
| srt | Actions | Terminal | skip | would open Terminal.app at the folder |
| vtt | Convert | SRT | PASS | talk.srt |
| vtt | Convert | VTT | PASS | talk.vtt |
| vtt | Convert | ASS | PASS | talk.ass |
| vtt | Convert | SSA | PASS | talk.ssa |
| vtt | Convert | SAMI | PASS | talk.smi |
| vtt | Convert | LRC | PASS | talk.lrc |
| vtt | Tools | Compress | off | Images and PDFs only |
| vtt | Tools | Metadata | off | Images only |
| vtt | Tools | Annotate | off | One image at a time |
| vtt | Tools | Redact | off | One image at a time |
| vtt | Tools | Crop | off | Images only |
| vtt | Tools | Add BG | off | Images only |
| vtt | Tools | Frame | off | Images only |
| vtt | Tools | Collage | off | Two or more images |
| vtt | Tools | QR Code | off | Images only |
| vtt | Tools | Resize | off | Images only |
| vtt | Tools | Grayscale | off | Images only |
| vtt | Tools | Adjust | off | One image at a time |
| vtt | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| vtt | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| vtt | Actions | Add to Float | off | No Float is open |
| vtt | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| vtt | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| vtt | Actions | Copy Path | PASS | path text copied |
| vtt | Actions | Zip | PASS | talk.vtt.zip |
| vtt | Actions | Terminal | skip | would open Terminal.app at the folder |
| ass | Convert | SRT | PASS | anime.srt |
| ass | Convert | VTT | PASS | anime.vtt |
| ass | Convert | ASS | PASS | anime.ass |
| ass | Convert | SSA | PASS | anime.ssa |
| ass | Convert | SAMI | PASS | anime.smi |
| ass | Convert | LRC | PASS | anime.lrc |
| ass | Tools | Compress | off | Images and PDFs only |
| ass | Tools | Metadata | off | Images only |
| ass | Tools | Annotate | off | One image at a time |
| ass | Tools | Redact | off | One image at a time |
| ass | Tools | Crop | off | Images only |
| ass | Tools | Add BG | off | Images only |
| ass | Tools | Frame | off | Images only |
| ass | Tools | Collage | off | Two or more images |
| ass | Tools | QR Code | off | Images only |
| ass | Tools | Resize | off | Images only |
| ass | Tools | Grayscale | off | Images only |
| ass | Tools | Adjust | off | One image at a time |
| ass | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| ass | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| ass | Actions | Add to Float | off | No Float is open |
| ass | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| ass | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| ass | Actions | Copy Path | PASS | path text copied |
| ass | Actions | Zip | PASS | anime.ass.zip |
| ass | Actions | Terminal | skip | would open Terminal.app at the folder |
| smi | Convert | SRT | PASS | drama.srt |
| smi | Convert | VTT | PASS | drama.vtt |
| smi | Convert | ASS | PASS | drama.ass |
| smi | Convert | SSA | PASS | drama.ssa |
| smi | Convert | SAMI | PASS | drama.smi |
| smi | Convert | LRC | PASS | drama.lrc |
| smi | Tools | Compress | off | Images and PDFs only |
| smi | Tools | Metadata | off | Images only |
| smi | Tools | Annotate | off | One image at a time |
| smi | Tools | Redact | off | One image at a time |
| smi | Tools | Crop | off | Images only |
| smi | Tools | Add BG | off | Images only |
| smi | Tools | Frame | off | Images only |
| smi | Tools | Collage | off | Two or more images |
| smi | Tools | QR Code | off | Images only |
| smi | Tools | Resize | off | Images only |
| smi | Tools | Grayscale | off | Images only |
| smi | Tools | Adjust | off | One image at a time |
| smi | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| smi | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| smi | Actions | Add to Float | off | No Float is open |
| smi | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| smi | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| smi | Actions | Copy Path | PASS | path text copied |
| smi | Actions | Zip | PASS | drama.smi.zip |
| smi | Actions | Terminal | skip | would open Terminal.app at the folder |
| lrc | Convert | SRT | PASS | song.srt |
| lrc | Convert | VTT | PASS | song.vtt |
| lrc | Convert | ASS | PASS | song.ass |
| lrc | Convert | SSA | PASS | song.ssa |
| lrc | Convert | SAMI | PASS | song.smi |
| lrc | Convert | LRC | PASS | song.lrc |
| lrc | Tools | Compress | off | Images and PDFs only |
| lrc | Tools | Metadata | off | Images only |
| lrc | Tools | Annotate | off | One image at a time |
| lrc | Tools | Redact | off | One image at a time |
| lrc | Tools | Crop | off | Images only |
| lrc | Tools | Add BG | off | Images only |
| lrc | Tools | Frame | off | Images only |
| lrc | Tools | Collage | off | Two or more images |
| lrc | Tools | QR Code | off | Images only |
| lrc | Tools | Resize | off | Images only |
| lrc | Tools | Grayscale | off | Images only |
| lrc | Tools | Adjust | off | One image at a time |
| lrc | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| lrc | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| lrc | Actions | Add to Float | off | No Float is open |
| lrc | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| lrc | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| lrc | Actions | Copy Path | PASS | path text copied |
| lrc | Actions | Zip | PASS | song.lrc.zip |
| lrc | Actions | Terminal | skip | would open Terminal.app at the folder |
| zip | Convert | Extract | PASS | photos |
| zip | Tools | Extract | PASS | photos |
| zip | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| zip | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| zip | Actions | Add to Float | off | No Float is open |
| zip | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| zip | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| zip | Actions | Copy Path | PASS | path text copied |
| zip | Actions | Zip | PASS | photos.zip.zip |
| zip | Actions | Terminal | skip | would open Terminal.app at the folder |
| 7z | Convert | Extract | PASS | photos |
| 7z | Tools | Extract | PASS | photos |
| 7z | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| 7z | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| 7z | Actions | Add to Float | off | No Float is open |
| 7z | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| 7z | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| 7z | Actions | Copy Path | PASS | path text copied |
| 7z | Actions | Zip | PASS | photos.7z.zip |
| 7z | Actions | Terminal | skip | would open Terminal.app at the folder |
| tar.gz | Convert | Extract | PASS | photos |
| tar.gz | Tools | Extract | PASS | photos |
| tar.gz | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| tar.gz | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| tar.gz | Actions | Add to Float | off | No Float is open |
| tar.gz | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| tar.gz | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| tar.gz | Actions | Copy Path | PASS | path text copied |
| tar.gz | Actions | Zip | PASS | photos.tar.gz.zip |
| tar.gz | Actions | Terminal | skip | would open Terminal.app at the folder |
| iso | Convert | Extract | PASS | disc |
| iso | Tools | Extract | PASS | disc |
| iso | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| iso | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| iso | Actions | Add to Float | off | No Float is open |
| iso | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| iso | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| iso | Actions | Copy Path | PASS | path text copied |
| iso | Actions | Zip | PASS | disc.iso.zip |
| iso | Actions | Terminal | skip | would open Terminal.app at the folder |
| gz | Convert | Extract | PASS | notes.md |
| gz | Tools | Extract | PASS | notes.md |
| gz | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| gz | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| gz | Actions | Add to Float | off | No Float is open |
| gz | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| gz | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| gz | Actions | Copy Path | PASS | path text copied |
| gz | Actions | Zip | PASS | notes.md.gz.zip |
| gz | Actions | Terminal | skip | would open Terminal.app at the folder |
| wmv | Convert | MP4 | PASS | legacy.mp4 |
| wmv | Convert | HEVC | PASS | legacy HEVC.mp4 |
| wmv | Convert | 720p | PASS | legacy 720p.mp4 |
| wmv | Convert | MOV | PASS | legacy.mov |
| wmv | Convert | M4V | PASS | legacy.m4v |
| wmv | Convert | MKV | PASS | legacy.mkv |
| wmv | Convert | AVI | PASS | legacy.avi |
| wmv | Convert | WebM | PASS | legacy.webm |
| wmv | Convert | GIF | PASS | legacy.gif |
| wmv | Convert | MP3 | PASS | legacy.mp3 |
| wmv | Convert | M4A | PASS | legacy.m4a |
| wmv | Tools | Compress | PASS | window "Compress"; saved: legacy compressed.mp4 |
| wmv | Tools | Trim | PASS | window "Edit legacy.wmv"; saved: legacy edited.mp4 |
| wmv | Tools | Split | PASS | window "Edit legacy.wmv"; saved: legacy part 1.mp4, legacy part 2.mp4 |
| wmv | Tools | Join | off | Two or more videos |
| wmv | Tools | Speed | PASS | window "Edit legacy.wmv"; saved: legacy edited.mp4 |
| wmv | Tools | Frames | PASS | window "Edit legacy.wmv"; saved: legacy 0m00.5s.png, legacy 0m01.2s.png |
| wmv | Tools | Crop | PASS | window "Edit legacy.wmv"; saved: legacy edited.mp4 |
| wmv | Tools | Redact | PASS | window "Edit legacy.wmv"; saved: legacy edited.mp4 |
| wmv | Tools | Subtitles | refused | legacy.wmv legacy.wmv has no subtitle tracks. |
| wmv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| wmv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| wmv | Actions | Add to Float | off | No Float is open |
| wmv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| wmv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| wmv | Actions | Copy Path | PASS | path text copied |
| wmv | Actions | Zip | PASS | legacy.wmv.zip |
| wmv | Actions | Terminal | skip | would open Terminal.app at the folder |
| flv | Convert | MP4 | PASS | flash.mp4 |
| flv | Convert | HEVC | PASS | flash HEVC.mp4 |
| flv | Convert | 720p | PASS | flash 720p.mp4 |
| flv | Convert | MOV | PASS | flash.mov |
| flv | Convert | M4V | PASS | flash.m4v |
| flv | Convert | MKV | PASS | flash.mkv |
| flv | Convert | AVI | PASS | flash.avi |
| flv | Convert | WebM | PASS | flash.webm |
| flv | Convert | GIF | PASS | flash.gif |
| flv | Convert | MP3 | PASS | flash.mp3 |
| flv | Convert | M4A | PASS | flash.m4a |
| flv | Tools | Compress | PASS | window "Compress"; saved: flash compressed.mp4 |
| flv | Tools | Trim | PASS | window "Edit flash.flv"; saved: flash edited.mp4 |
| flv | Tools | Split | PASS | window "Edit flash.flv"; saved: flash part 1.mp4, flash part 2.mp4 |
| flv | Tools | Join | off | Two or more videos |
| flv | Tools | Speed | PASS | window "Edit flash.flv"; saved: flash edited.mp4 |
| flv | Tools | Frames | PASS | window "Edit flash.flv"; saved: flash 0m00.5s.png, flash 0m01.2s.png |
| flv | Tools | Crop | PASS | window "Edit flash.flv"; saved: flash edited.mp4 |
| flv | Tools | Redact | PASS | window "Edit flash.flv"; saved: flash edited.mp4 |
| flv | Tools | Subtitles | refused | flash.flv flash.flv has no subtitle tracks. |
| flv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| flv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| flv | Actions | Add to Float | off | No Float is open |
| flv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| flv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| flv | Actions | Copy Path | PASS | path text copied |
| flv | Actions | Zip | PASS | flash.flv.zip |
| flv | Actions | Terminal | skip | would open Terminal.app at the folder |
| mpg | Convert | MP4 | PASS | broadcast.mp4 |
| mpg | Convert | HEVC | PASS | broadcast HEVC.mp4 |
| mpg | Convert | 720p | PASS | broadcast 720p.mp4 |
| mpg | Convert | MOV | PASS | broadcast.mov |
| mpg | Convert | M4V | PASS | broadcast.m4v |
| mpg | Convert | MKV | PASS | broadcast.mkv |
| mpg | Convert | AVI | PASS | broadcast.avi |
| mpg | Convert | WebM | PASS | broadcast.webm |
| mpg | Convert | GIF | PASS | broadcast.gif |
| mpg | Convert | MP3 | PASS | broadcast.mp3 |
| mpg | Convert | M4A | PASS | broadcast.m4a |
| mpg | Tools | Compress | PASS | window "Compress"; saved: broadcast compressed.mp4 |
| mpg | Tools | Trim | PASS | window "Edit broadcast.mpg"; saved: broadcast edited.mp4 |
| mpg | Tools | Split | PASS | window "Edit broadcast.mpg"; saved: broadcast part 1.mp4, broadcast part 2.mp4 |
| mpg | Tools | Join | off | Two or more videos |
| mpg | Tools | Speed | PASS | window "Edit broadcast.mpg"; saved: broadcast edited.mp4 |
| mpg | Tools | Frames | PASS | window "Edit broadcast.mpg"; saved: broadcast 0m00.5s.png, broadcast 0m01.2s.png |
| mpg | Tools | Crop | PASS | window "Edit broadcast.mpg"; saved: broadcast edited.mp4 |
| mpg | Tools | Redact | PASS | window "Edit broadcast.mpg"; saved: broadcast edited.mp4 |
| mpg | Tools | Subtitles | refused | broadcast.mpg broadcast.mpg has no subtitle tracks. |
| mpg | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| mpg | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| mpg | Actions | Add to Float | off | No Float is open |
| mpg | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| mpg | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| mpg | Actions | Copy Path | PASS | path text copied |
| mpg | Actions | Zip | PASS | broadcast.mpg.zip |
| mpg | Actions | Terminal | skip | would open Terminal.app at the folder |
| ts | Convert | MP4 | PASS | stream.mp4 |
| ts | Convert | HEVC | PASS | stream HEVC.mp4 |
| ts | Convert | 720p | PASS | stream 720p.mp4 |
| ts | Convert | MOV | PASS | stream.mov |
| ts | Convert | M4V | PASS | stream.m4v |
| ts | Convert | MKV | PASS | stream.mkv |
| ts | Convert | AVI | PASS | stream.avi |
| ts | Convert | WebM | PASS | stream.webm |
| ts | Convert | GIF | PASS | stream.gif |
| ts | Convert | MP3 | PASS | stream.mp3 |
| ts | Convert | M4A | PASS | stream.m4a |
| ts | Tools | Compress | PASS | window "Compress"; saved: stream compressed.mp4 |
| ts | Tools | Trim | PASS | window "Edit stream.ts"; saved: stream edited.mp4 |
| ts | Tools | Split | PASS | window "Edit stream.ts"; saved: stream part 1.mp4, stream part 2.mp4 |
| ts | Tools | Join | off | Two or more videos |
| ts | Tools | Speed | PASS | window "Edit stream.ts"; saved: stream edited.mp4 |
| ts | Tools | Frames | PASS | window "Edit stream.ts"; saved: stream 0m00.5s.png, stream 0m01.2s.png |
| ts | Tools | Crop | PASS | window "Edit stream.ts"; saved: stream edited.mp4 |
| ts | Tools | Redact | PASS | window "Edit stream.ts"; saved: stream edited.mp4 |
| ts | Tools | Subtitles | refused | stream.ts stream.ts has no subtitle tracks. |
| ts | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| ts | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| ts | Actions | Add to Float | off | No Float is open |
| ts | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| ts | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| ts | Actions | Copy Path | PASS | path text copied |
| ts | Actions | Zip | PASS | stream.ts.zip |
| ts | Actions | Terminal | skip | would open Terminal.app at the folder |
| 3gp | Convert | MP4 | PASS | phone.mp4 |
| 3gp | Convert | HEVC | PASS | phone HEVC.mp4 |
| 3gp | Convert | 720p | PASS | phone 720p.mp4 |
| 3gp | Convert | MOV | PASS | phone.mov |
| 3gp | Convert | M4V | PASS | phone.m4v |
| 3gp | Convert | MKV | PASS | phone.mkv |
| 3gp | Convert | AVI | PASS | phone.avi |
| 3gp | Convert | WebM | PASS | phone.webm |
| 3gp | Convert | GIF | PASS | phone.gif |
| 3gp | Convert | MP3 | PASS | phone.mp3 |
| 3gp | Convert | M4A | PASS | phone.m4a |
| 3gp | Tools | Compress | PASS | window "Compress"; saved: phone compressed.mp4 |
| 3gp | Tools | Trim | PASS | window "Edit phone.3gp"; saved: phone edited.mp4 |
| 3gp | Tools | Split | PASS | window "Edit phone.3gp"; saved: phone part 1.mp4, phone part 2.mp4 |
| 3gp | Tools | Join | off | Two or more videos |
| 3gp | Tools | Speed | PASS | window "Edit phone.3gp"; saved: phone edited.mp4 |
| 3gp | Tools | Frames | PASS | window "Edit phone.3gp"; saved: phone 0m00.5s.png, phone 0m01.2s.png |
| 3gp | Tools | Crop | PASS | window "Edit phone.3gp"; saved: phone edited.mp4 |
| 3gp | Tools | Redact | PASS | window "Edit phone.3gp"; saved: phone edited.mp4 |
| 3gp | Tools | Subtitles | refused | phone.3gp phone.3gp has no subtitle tracks. |
| 3gp | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| 3gp | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| 3gp | Actions | Add to Float | off | No Float is open |
| 3gp | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| 3gp | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| 3gp | Actions | Copy Path | PASS | path text copied |
| 3gp | Actions | Zip | PASS | phone.3gp.zip |
| 3gp | Actions | Terminal | skip | would open Terminal.app at the folder |
| ogv | Convert | MP4 | PASS | open.mp4 |
| ogv | Convert | HEVC | PASS | open HEVC.mp4 |
| ogv | Convert | 720p | PASS | open 720p.mp4 |
| ogv | Convert | MOV | PASS | open.mov |
| ogv | Convert | M4V | PASS | open.m4v |
| ogv | Convert | MKV | PASS | open.mkv |
| ogv | Convert | AVI | PASS | open.avi |
| ogv | Convert | WebM | PASS | open.webm |
| ogv | Convert | GIF | PASS | open.gif |
| ogv | Convert | MP3 | PASS | open.mp3 |
| ogv | Convert | M4A | PASS | open.m4a |
| ogv | Tools | Compress | refused | window "Compress"; saved: open.ogv open.ogv is already as small as it gets. |
| ogv | Tools | Trim | PASS | window "Edit open.ogv"; saved: open edited.mp4 |
| ogv | Tools | Split | PASS | window "Edit open.ogv"; saved: open part 1.mp4, open part 2.mp4 |
| ogv | Tools | Join | off | Two or more videos |
| ogv | Tools | Speed | PASS | window "Edit open.ogv"; saved: open edited.mp4 |
| ogv | Tools | Frames | PASS | window "Edit open.ogv"; saved: open 0m00.5s.png, open 0m01.2s.png |
| ogv | Tools | Crop | PASS | window "Edit open.ogv"; saved: open edited.mp4 |
| ogv | Tools | Redact | PASS | window "Edit open.ogv"; saved: open edited.mp4 |
| ogv | Tools | Subtitles | refused | open.ogv open.ogv has no subtitle tracks. |
| ogv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| ogv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| ogv | Actions | Add to Float | off | No Float is open |
| ogv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| ogv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| ogv | Actions | Copy Path | PASS | path text copied |
| ogv | Actions | Zip | PASS | open.ogv.zip |
| ogv | Actions | Terminal | skip | would open Terminal.app at the folder |
| vob | Convert | MP4 | PASS | disc.mp4 |
| vob | Convert | HEVC | PASS | disc HEVC.mp4 |
| vob | Convert | 720p | PASS | disc 720p.mp4 |
| vob | Convert | MOV | PASS | disc.mov |
| vob | Convert | M4V | PASS | disc.m4v |
| vob | Convert | MKV | PASS | disc.mkv |
| vob | Convert | AVI | PASS | disc.avi |
| vob | Convert | WebM | PASS | disc.webm |
| vob | Convert | GIF | PASS | disc.gif |
| vob | Convert | MP3 | PASS | disc.mp3 |
| vob | Convert | M4A | PASS | disc.m4a |
| vob | Tools | Compress | PASS | window "Compress"; saved: disc compressed.mp4 |
| vob | Tools | Trim | PASS | window "Edit disc.vob"; saved: disc edited.mp4 |
| vob | Tools | Split | PASS | window "Edit disc.vob"; saved: disc part 1.mp4, disc part 2.mp4 |
| vob | Tools | Join | off | Two or more videos |
| vob | Tools | Speed | PASS | window "Edit disc.vob"; saved: disc edited.mp4 |
| vob | Tools | Frames | PASS | window "Edit disc.vob"; saved: disc 0m00.5s.png, disc 0m01.2s.png |
| vob | Tools | Crop | PASS | window "Edit disc.vob"; saved: disc edited.mp4 |
| vob | Tools | Redact | PASS | window "Edit disc.vob"; saved: disc edited.mp4 |
| vob | Tools | Subtitles | refused | disc.vob disc.vob has no subtitle tracks. |
| vob | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| vob | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| vob | Actions | Add to Float | off | No Float is open |
| vob | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| vob | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| vob | Actions | Copy Path | PASS | path text copied |
| vob | Actions | Zip | PASS | disc.vob.zip |
| vob | Actions | Terminal | skip | would open Terminal.app at the folder |

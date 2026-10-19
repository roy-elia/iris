# Feature self-test

2026-10-19, 00:39

**282 passed, 0 failed, 7 correctly refused (nothing to find in that input), 63 skipped (system UI), 129 disabled for the input (with the reason shown).**

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
| png | Tools | Compress | PASS | window "Compress"; saved: scene compressed.heic |
| png | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.png |
| png | Tools | Annotate | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Tools | Redact | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Tools | Crop | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.png |
| png | Tools | Frame | PASS | window "Frame"; saved: scene framed.png |
| png | Tools | Collage | off | Two or more images |
| png | Tools | QR Code | refused | scene.png No QR codes found. |
| png | Tools | Adjust | PASS | window "Edit scene.png"; saved: scene edited.png |
| png | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| png | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| png | Actions | Add to Float | off | No Float is open |
| png | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| png | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| png | Actions | Copy Path | PASS | path text copied |
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
| jpg | Tools | Compress | PASS | window "Compress"; saved: scene compressed.jpg |
| jpg | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.jpg |
| jpg | Tools | Annotate | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Tools | Redact | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Tools | Crop | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.jpg |
| jpg | Tools | Frame | PASS | window "Frame"; saved: scene framed.png |
| jpg | Tools | Collage | off | Two or more images |
| jpg | Tools | QR Code | refused | scene.jpg No QR codes found. |
| jpg | Tools | Adjust | PASS | window "Edit scene.jpg"; saved: scene edited.jpg |
| jpg | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| jpg | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| jpg | Actions | Add to Float | off | No Float is open |
| jpg | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| jpg | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| jpg | Actions | Copy Path | PASS | path text copied |
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
| heic | Tools | Compress | PASS | window "Compress"; saved: scene compressed.heic |
| heic | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.heic |
| heic | Tools | Annotate | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Tools | Redact | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Tools | Crop | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.heic |
| heic | Tools | Frame | PASS | window "Frame"; saved: scene framed.png |
| heic | Tools | Collage | off | Two or more images |
| heic | Tools | QR Code | refused | scene.heic No QR codes found. |
| heic | Tools | Adjust | PASS | window "Edit scene.heic"; saved: scene edited.heic |
| heic | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| heic | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| heic | Actions | Add to Float | off | No Float is open |
| heic | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| heic | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| heic | Actions | Copy Path | PASS | path text copied |
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
| svg | Tools | Compress | PASS | window "Compress"; saved: logo compressed.heic |
| svg | Tools | Metadata | off | Not for SVG files |
| svg | Tools | Annotate | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Tools | Redact | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Tools | Crop | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Tools | Add BG | PASS | window "Background"; saved: logo no-bg.png |
| svg | Tools | Frame | PASS | window "Frame"; saved: logo framed.png |
| svg | Tools | Collage | off | Two or more images |
| svg | Tools | QR Code | refused | logo.svg No QR codes found. |
| svg | Tools | Adjust | PASS | window "Edit logo.svg"; saved: logo edited.png |
| svg | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| svg | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| svg | Actions | Add to Float | off | No Float is open |
| svg | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| svg | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| svg | Actions | Copy Path | PASS | path text copied |
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
| qr | Tools | Compress | PASS | window "Compress"; saved: menu-qr compressed.heic |
| qr | Tools | Metadata | PASS | window "Metadata"; saved: menu-qr metadata.png |
| qr | Tools | Annotate | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Tools | Redact | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Tools | Crop | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Tools | Add BG | refused | window "Background"; saved: menu-qr.png No clear subject was found in menu-qr.png. |
| qr | Tools | Frame | PASS | window "Frame"; saved: menu-qr framed.png |
| qr | Tools | Collage | off | Two or more images |
| qr | Tools | QR Code | PASS | read: https://example.com/menu |
| qr | Tools | Adjust | PASS | window "Edit menu-qr.png"; saved: menu-qr edited.png |
| qr | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| qr | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| qr | Actions | Add to Float | off | No Float is open |
| qr | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| qr | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| qr | Actions | Copy Path | PASS | path text copied |
| qr | Actions | Terminal | skip | would open Terminal.app at the folder |
| images×2 | Convert | PNG | PASS | scene.png, scene (1).png |
| images×2 | Convert | PDF | PASS | Images.pdf |
| images×2 | Convert | JPEG | PASS | scene.jpg, scene (1).jpg |
| images×2 | Convert | HEIC | PASS | scene.heic, scene (1).heic |
| images×2 | Convert | AVIF | PASS | scene.avif, scene (1).avif |
| images×2 | Convert | TIFF | PASS | scene.tiff, scene (1).tiff |
| images×2 | Convert | BMP | PASS | scene.bmp, scene (1).bmp |
| images×2 | Convert | WebP | PASS | scene.webp, scene (1).webp |
| images×2 | Convert | GIF | PASS | scene.gif, scene (1).gif |
| images×2 | Tools | Compress | PASS | window "Compress"; saved: scene compressed.heic, scene compressed.jpg |
| images×2 | Tools | Metadata | PASS | window "Metadata"; saved: scene metadata.png, scene metadata.jpg |
| images×2 | Tools | Annotate | off | One image at a time |
| images×2 | Tools | Redact | off | One image at a time |
| images×2 | Tools | Crop | PASS | window "Edit scene.png"; saved: scene edited.png, scene edited.jpg |
| images×2 | Tools | Add BG | PASS | window "Background"; saved: scene no-bg.png, scene no-bg.jpg |
| images×2 | Tools | Frame | PASS | window "Frame"; saved: scene framed.png, scene framed (1).png |
| images×2 | Tools | Collage | PASS | window "Collage"; saved: Collage.png |
| images×2 | Tools | QR Code | refused | scene.png No QR codes found.; scene.jpg No QR codes found. |
| images×2 | Tools | Adjust | off | One image at a time |
| images×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| images×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| images×2 | Actions | Add to Float | off | No Float is open |
| images×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| images×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| images×2 | Actions | Copy Path | PASS | path text copied |
| images×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| mp4 | Convert | MP4 | PASS | clip.mp4 |
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
| mp4 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| mp4 | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| mp4 | Actions | Add to Float | off | No Float is open |
| mp4 | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| mp4 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| mp4 | Actions | Copy Path | PASS | path text copied |
| mp4 | Actions | Terminal | skip | would open Terminal.app at the folder |
| videos×2 | Convert | MP4 | PASS | clip.mp4, intro.mp4 |
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
| videos×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| videos×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| videos×2 | Actions | Add to Float | off | No Float is open |
| videos×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| videos×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| videos×2 | Actions | Copy Path | PASS | path text copied |
| videos×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| wav | Convert | MP3 | PASS | voice.mp3 |
| wav | Convert | M4A | PASS | voice.m4a |
| wav | Convert | AAC | PASS | voice.aac |
| wav | Convert | WAV | PASS | voice.wav |
| wav | Convert | AIFF | PASS | voice.aiff |
| wav | Convert | FLAC | PASS | voice.flac |
| wav | Convert | OGG | PASS | voice.ogg |
| wav | Convert | Opus | PASS | voice.opus |
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
| wav | Actions | Terminal | skip | would open Terminal.app at the folder |
| audio×2 | Convert | MP3 | PASS | voice.mp3, song.mp3 |
| audio×2 | Convert | M4A | PASS | voice.m4a, song.m4a |
| audio×2 | Convert | AAC | PASS | voice.aac, song.aac |
| audio×2 | Convert | WAV | PASS | voice.wav, song.wav |
| audio×2 | Convert | AIFF | PASS | voice.aiff, song.aiff |
| audio×2 | Convert | FLAC | PASS | voice.flac, song.flac |
| audio×2 | Convert | OGG | PASS | voice.ogg, song.ogg |
| audio×2 | Convert | Opus | PASS | voice.opus, song.opus |
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
| audio×2 | Actions | Terminal | skip | would open Terminal.app at the folder |
| pdf | Convert | PNG | PASS | deck page 1.png, deck page 2.png, deck page 3.png +1 |
| pdf | Convert | JPEG | PASS | deck page 1.jpg, deck page 2.jpg, deck page 3.jpg +1 |
| pdf | Convert | DOCX | PASS | deck.docx |
| pdf | Convert | RTF | PASS | deck.rtf |
| pdf | Convert | Text | PASS | deck.txt |
| pdf | Convert | Markdown | PASS | deck.md |
| pdf | Convert | HTML | PASS | deck.html |
| pdf | Convert | EPUB | PASS | deck.epub |
| pdf | Convert | EPUB Pages | PASS | deck.epub |
| pdf | Tools | Organize | PASS | window "Organize deck.pdf"; saved: deck organized.pdf |
| pdf | Tools | Compress | PASS | window "Compress"; saved: deck compressed.pdf |
| pdf | Tools | Merge | off | Two or more PDFs |
| pdf | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| pdf | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| pdf | Actions | Add to Float | off | No Float is open |
| pdf | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| pdf | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| pdf | Actions | Copy Path | PASS | path text copied |
| pdf | Actions | Terminal | skip | would open Terminal.app at the folder |
| pdfs×2 | Convert | PNG | PASS | deck page 1.png, deck page 2.png, deck page 3.png +3 |
| pdfs×2 | Convert | JPEG | PASS | deck page 1.jpg, deck page 2.jpg, deck page 3.jpg +3 |
| pdfs×2 | Convert | DOCX | PASS | deck.docx, appendix.docx |
| pdfs×2 | Convert | RTF | PASS | deck.rtf, appendix.rtf |
| pdfs×2 | Convert | Text | PASS | deck.txt, appendix.txt |
| pdfs×2 | Convert | Markdown | PASS | deck.md, appendix.md |
| pdfs×2 | Convert | HTML | PASS | deck.html, appendix.html |
| pdfs×2 | Convert | EPUB | PASS | deck.epub, appendix.epub |
| pdfs×2 | Convert | EPUB Pages | PASS | deck.epub, appendix.epub |
| pdfs×2 | Tools | Organize | off | One PDF at a time |
| pdfs×2 | Tools | Compress | refused | window "Compress"; saved: appendix.pdf appendix.pdf is already as small as it gets. |
| pdfs×2 | Tools | Merge | PASS | Merged.pdf |
| pdfs×2 | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| pdfs×2 | Actions | Float | PASS | Float with 2 file(s) shown, then closed |
| pdfs×2 | Actions | Add to Float | off | No Float is open |
| pdfs×2 | Actions | Copy | PASS | 2 file(s) on the pasteboard |
| pdfs×2 | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| pdfs×2 | Actions | Copy Path | PASS | path text copied |
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
| docx | Tools | Adjust | off | One image at a time |
| docx | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| docx | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| docx | Actions | Add to Float | off | No Float is open |
| docx | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| docx | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| docx | Actions | Copy Path | PASS | path text copied |
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
| rtf | Tools | Adjust | off | One image at a time |
| rtf | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| rtf | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| rtf | Actions | Add to Float | off | No Float is open |
| rtf | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| rtf | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| rtf | Actions | Copy Path | PASS | path text copied |
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
| md | Tools | Adjust | off | One image at a time |
| md | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| md | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| md | Actions | Add to Float | off | No Float is open |
| md | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| md | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| md | Actions | Copy Path | PASS | path text copied |
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
| html | Tools | Adjust | off | One image at a time |
| html | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| html | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| html | Actions | Add to Float | off | No Float is open |
| html | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| html | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| html | Actions | Copy Path | PASS | path text copied |
| html | Actions | Terminal | skip | would open Terminal.app at the folder |
| csv | Convert | PDF | PASS | scores.pdf |
| csv | Convert | DOCX | PASS | scores.docx |
| csv | Convert | RTF | PASS | scores.rtf |
| csv | Convert | Text | PASS | scores.txt |
| csv | Convert | Markdown | PASS | scores.md |
| csv | Convert | HTML | PASS | scores.html |
| csv | Convert | EPUB | PASS | scores.epub |
| csv | Convert | Pages | off | Needs Pages |
| csv | Tools | Compress | off | Images and PDFs only |
| csv | Tools | Metadata | off | Images only |
| csv | Tools | Annotate | off | One image at a time |
| csv | Tools | Redact | off | One image at a time |
| csv | Tools | Crop | off | Images only |
| csv | Tools | Add BG | off | Images only |
| csv | Tools | Frame | off | Images only |
| csv | Tools | Collage | off | Two or more images |
| csv | Tools | QR Code | off | Images only |
| csv | Tools | Adjust | off | One image at a time |
| csv | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| csv | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| csv | Actions | Add to Float | off | No Float is open |
| csv | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| csv | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| csv | Actions | Copy Path | PASS | path text copied |
| csv | Actions | Terminal | skip | would open Terminal.app at the folder |
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
| clipping | Tools | Adjust | off | One image at a time |
| clipping | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| clipping | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| clipping | Actions | Add to Float | off | No Float is open |
| clipping | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| clipping | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| clipping | Actions | Copy Path | PASS | path text copied |
| clipping | Actions | Terminal | skip | would open Terminal.app at the folder |
| srt | Convert | SRT | PASS | film.srt |
| srt | Convert | VTT | PASS | film.vtt |
| srt | Tools | Compress | off | Images and PDFs only |
| srt | Tools | Metadata | off | Images only |
| srt | Tools | Annotate | off | One image at a time |
| srt | Tools | Redact | off | One image at a time |
| srt | Tools | Crop | off | Images only |
| srt | Tools | Add BG | off | Images only |
| srt | Tools | Frame | off | Images only |
| srt | Tools | Collage | off | Two or more images |
| srt | Tools | QR Code | off | Images only |
| srt | Tools | Adjust | off | One image at a time |
| srt | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| srt | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| srt | Actions | Add to Float | off | No Float is open |
| srt | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| srt | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| srt | Actions | Copy Path | PASS | path text copied |
| srt | Actions | Terminal | skip | would open Terminal.app at the folder |
| vtt | Convert | SRT | PASS | talk.srt |
| vtt | Convert | VTT | PASS | talk.vtt |
| vtt | Tools | Compress | off | Images and PDFs only |
| vtt | Tools | Metadata | off | Images only |
| vtt | Tools | Annotate | off | One image at a time |
| vtt | Tools | Redact | off | One image at a time |
| vtt | Tools | Crop | off | Images only |
| vtt | Tools | Add BG | off | Images only |
| vtt | Tools | Frame | off | Images only |
| vtt | Tools | Collage | off | Two or more images |
| vtt | Tools | QR Code | off | Images only |
| vtt | Tools | Adjust | off | One image at a time |
| vtt | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| vtt | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| vtt | Actions | Add to Float | off | No Float is open |
| vtt | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| vtt | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| vtt | Actions | Copy Path | PASS | path text copied |
| vtt | Actions | Terminal | skip | would open Terminal.app at the folder |
| zip | Convert | Extract | PASS | photos |
| zip | Tools | Extract | PASS | photos |
| zip | Actions | AirDrop | skip | AirDrop service available; sending needs a person |
| zip | Actions | Float | PASS | Float with 1 file(s) shown, then closed |
| zip | Actions | Add to Float | off | No Float is open |
| zip | Actions | Copy | PASS | 1 file(s) on the pasteboard |
| zip | Actions | Move | skip | opens a folder picker (FileActions.move is unit-tested) |
| zip | Actions | Copy Path | PASS | path text copied |
| zip | Actions | Terminal | skip | would open Terminal.app at the folder |

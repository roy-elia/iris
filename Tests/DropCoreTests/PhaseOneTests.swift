import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

private func size(_ url: URL) -> Int64 { CompressOps.fileSize(url) }

private func pixelSize(_ url: URL) -> (Int, Int) {
  let props = Fixtures.properties(of: url)
  return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
}

private func writeNoisyPNG(_ url: URL, side: Int = 600) throws -> URL {
  try Fixtures.writeCGImage(Fixtures.noisyImage(width: side, height: side), to: url)
}

/// A three-frame looping GIF, frames red/green/blue at 0.2s each.
private func writeAnimatedGIF(_ url: URL) throws -> URL {
  let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 3, nil)!
  CGImageDestinationSetProperties(
    dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
  for (r, g, b) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)] {
    let ctx = CGContext(
      data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
    CGImageDestinationAddImage(
      dest, ctx.makeImage()!,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
  }
  #expect(CGImageDestinationFinalize(dest))
  return url
}

@Suite struct ConversionTests {
  @Test(.enabled(if: ToolLocator.isAvailable(.cwebp)))
  func convertsToWebP() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png", width: 64, height: 32)
    let result = await Processor(settings: AppSettings()).run(
      .convert(.webp, quality: 0.8), on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.pathExtension == "webp")
    #expect(Fixtures.typeIdentifier(of: out) == ImageFormat.webp.typeIdentifier)
    #expect(pixelSize(out) == (64, 32))
  }

  @Test(.enabled(if: ToolLocator.isAvailable(.cwebp) && ToolLocator.isAvailable(.exiftool)))
  func webPKeepsMetadataWhenAsked() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.jpg"), withMetadata: true)
    let out = dir.file("a.webp")
    try await ImageConvert.convert(src, to: .webp, quality: 0.8, destination: out)
    let fields = try await MetadataOps.read(out)
    #expect(fields.contains { $0.tag == "Artist" && $0.value == "Someone" })
  }

  @Test func animatedGIFKeepsEveryFrame() async throws {
    let dir = try TempDir()
    let src = try writeAnimatedGIF(dir.file("anim.gif"))
    let out = dir.file("out.gif")
    try await ImageConvert.convert(src, to: .gif, quality: 1, destination: out)
    #expect(ImageConvert.frameCount(out) == 3)
    let source = CGImageSourceCreateWithURL(out as CFURL, nil)!
    #expect(abs(ImageConvert.frameDelay(source, index: 1) - 0.2) < 0.02)
  }

  @Test func stillImageBecomesGIF() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png")
    let result = await Processor(settings: AppSettings()).run(.convert(.gif, quality: 1), on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(Fixtures.typeIdentifier(of: out) == ImageFormat.gif.typeIdentifier)
  }

  @Test func svgIsRasterisedSharply() async throws {
    let dir = try TempDir()
    let svg = dir.file("logo.svg")
    try Data(
      ##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><rect width="100" height="50" fill="#0a8"/></svg>"##
        .utf8
    ).write(to: svg)
    #expect(FileKind(url: svg) == .image(.svg))
    let result = await Processor(settings: AppSettings()).run(.convert(.png, quality: 1), on: try load(svg))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let (w, h) = pixelSize(out)
    #expect(w == 2048 && h == 1024)
  }

  @Test func metadataIsKeptOrDroppedPerFormatSetting() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.jpg"), withMetadata: true)
    let kept = dir.file("kept.heic")
    let dropped = dir.file("dropped.heic")
    try await ImageConvert.convert(src, to: .heic, quality: 0.8, destination: kept)
    try await ImageConvert.convert(
      src, to: .heic, quality: 0.8, options: FormatSettings(preserveMetadata: false), destination: dropped)
    #expect(try ImageOps.hasLocation(kept))
    #expect(try !ImageOps.hasLocation(dropped))
  }
}

@Suite struct TargetSizeTests {
  @Test func fitsUnderTheTarget() async throws {
    let dir = try TempDir()
    let src = try writeNoisyPNG(dir.file("noise.png"))
    let target: Int64 = 40_000
    #expect(size(src) > target)
    let result = await Processor(settings: AppSettings()).run(
      .compressToSize(bytes: target), on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.pathExtension == "jpg")
    #expect(size(out) <= target)
    #expect(size(out) > target / 3, "should use most of the budget, not over-compress")
  }

  @Test func shrinksDimensionsForVerySmallTargets() async throws {
    let dir = try TempDir()
    let src = try writeNoisyPNG(dir.file("noise.png"))
    let out = dir.file("small.jpg")
    try await TargetSizeOps.compress(src, target: 4_000, format: .jpeg, destination: out)
    #expect(size(out) <= 4_000)
    #expect(pixelSize(out).0 < 600)
  }

  @Test func rejectsTargetsThatCantWork() async throws {
    #expect(
      TargetSizeOps.validate(target: 500, sourceSize: 10_000, name: "a")
        == "Enter a target size of at least 1 KB.")
    #expect(
      TargetSizeOps.validate(target: 20_000, sourceSize: 10_000, name: "a")?.contains("cannot exceed") == true
    )
    #expect(TargetSizeOps.validate(target: 5_000, sourceSize: 10_000, name: "a") == nil)
  }

  @Test func transparentSourcesKeepTransparency() throws {
    let dir = try TempDir()
    let url = try Fixtures.writeCGImage(transparentImage(), to: dir.file("t.png"))
    let format = TargetSizeOps.outputFormat(for: url)
    #expect(format.supportsAlpha)
  }

  private func transparentImage() -> CGImage {
    let ctx = CGContext(
      data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
    ctx.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
    return ctx.makeImage()!
  }
}

@Suite(.enabled(if: ToolLocator.isAvailable(.exiftool))) struct MetadataEditorTests {
  @Test func readsEditsAndRemovesLocation() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.jpg"), withMetadata: true)
    let before = try await MetadataOps.read(src)
    #expect(MetadataOps.value(of: EditableField.all[2], in: before) == "Someone")  // Artist
    #expect(before.contains { $0.group.hasPrefix("GPS") })

    let edits = [
      MetadataEdit(tag: "EXIF:Artist", value: "Rodin"), MetadataEdit(tag: "XMP-dc:Title", value: "Café"),
      .removeLocation,
    ]
    let result = await Processor(settings: AppSettings()).run(.editMetadata(edits), on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "a metadata.jpg")
    let after = try await MetadataOps.read(out)
    #expect(MetadataOps.value(of: EditableField.all[2], in: after) == "Rodin")
    #expect(MetadataOps.value(of: EditableField.all[0], in: after) == "Café")
    #expect(!after.contains { $0.group.hasPrefix("GPS") })
    // The original is untouched.
    #expect(MetadataOps.value(of: EditableField.all[2], in: try await MetadataOps.read(src)) == "Someone")
  }

  @Test func emptyEditsAreRefused() throws {
    let dir = try TempDir()
    let files = try load(Fixtures.writeImage(to: dir.file("a.jpg")))
    #expect(Processor.validate(.editMetadata([]), files: files) == "There are no metadata changes to save.")
  }
}

@Suite struct MarkupTests {
  private func render(_ marks: [Mark], style: RedactStyle = .blackout, redactions: [NormRect] = []) throws
    -> CGImage
  {
    let dir = try TempDir()
    let src = try Fixtures.writeCGImage(Fixtures.noisyImage(width: 200, height: 200), to: dir.file("n.png"))
    return try EditOps.render(
      src, recipe: EditRecipe(redactions: redactions, redactStyle: style, marks: marks))
  }

  @Test func calloutFillsWithItsColour() throws {
    let blue = RGBA(red: 0, green: 0, blue: 1)
    let image = try render([.callout(number: 3, at: NormPoint(x: 0.5, y: 0.5), color: blue, radius: 0.1)])
    // Just inside the disc's edge, away from the white numeral.
    let px = Fixtures.pixel(image, x: 100, y: 84)
    #expect(px[2] > 240 && px[0] < 15 && px[1] < 15)
  }

  @Test func filledRectangleCoversItsArea() throws {
    let image = try render([
      .rectangle(NormRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), color: .black, width: 0.01, filled: true)
    ])
    #expect(Fixtures.pixel(image, x: 50, y: 50)[0...2] == [0, 0, 0])
  }

  @Test func arrowTextHighlightMagnifierAndStickerAllDraw() throws {
    let dir = try TempDir()
    let sticker = try Fixtures.writeImage(to: dir.file("s.png"), type: "public.png")
    let base = try render([])
    let marks: [Mark] = [
      .arrow(from: NormPoint(x: 0.1, y: 0.9), to: NormPoint(x: 0.9, y: 0.1), color: .white, width: 0.02),
      .text("Hello", at: NormPoint(x: 0.05, y: 0.05), color: .white, size: 0.08, boxWidth: 0.5),
      .highlight(NormRect(x: 0.6, y: 0.6, width: 0.3, height: 0.1), color: RGBA(red: 1, green: 1, blue: 0)),
      .magnifier(source: NormPoint(x: 0.2, y: 0.2), at: NormPoint(x: 0.7, y: 0.3), radius: 0.15, zoom: 2),
      .sticker(path: sticker.path, rect: NormRect(x: 0.0, y: 0.7, width: 0.3, height: 0.3)),
    ]
    for mark in marks {
      let image = try render([mark])
      #expect(differingPixels(base, image) > 50, "\(mark) should change the image")
    }
  }

  @Test func blurRedactionDiffersFromPixelateAndBlackout() throws {
    let region = [NormRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)]
    let blur = try render([], style: .blur, redactions: region)
    let pixelate = try render([], style: .pixelate, redactions: region)
    let base = try render([])
    #expect(differingPixels(base, blur) > 1000)
    #expect(differingPixels(blur, pixelate) > 1000)
    // Outside the region nothing changes.
    #expect(Fixtures.pixel(blur, x: 5, y: 5) == Fixtures.pixel(base, x: 5, y: 5))
  }

  @Test func batchCropAppliesToEveryImage() async throws {
    let dir = try TempDir()
    let a = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png", width: 100, height: 50)
    let b = try Fixtures.writeImage(to: dir.file("b.png"), type: "public.png", width: 40, height: 40)
    let crop = EditRecipe(crop: NormRect(x: 0, y: 0, width: 0.5, height: 0.5))
    let result = await Processor(settings: AppSettings()).run(.batchEdit(crop), on: try load(a, b))
    #expect(result.outputs.count == 2)
    #expect(pixelSize(result.outputs[0]) == (50, 25))
    #expect(pixelSize(result.outputs[1]) == (20, 20))
  }

  private func differingPixels(_ a: CGImage, _ b: CGImage) -> Int {
    var count = 0
    for y in stride(from: 0, to: a.height, by: 2) {
      for x in stride(from: 0, to: a.width, by: 2)
      where Fixtures.pixel(a, x: x, y: y) != Fixtures.pixel(b, x: x, y: y) {
        count += 1
      }
    }
    return count
  }
}

@Suite struct CompositionTests {
  @Test func frameAddsPaddingAndRoundedTransparentCorners() throws {
    let image = Fixtures.image(width: 200, height: 100)
    let framed = try FrameOps.render(
      image, recipe: FrameRecipe(padding: 0.1, cornerRadius: 0.2, shadow: false, background: .transparent))
    #expect(framed.width == 240 && framed.height == 140)
    // Corner of the image area is clipped (transparent); its centre is the image colour.
    #expect(Fixtures.pixel(framed, x: 21, y: 21)[3] == 0)
    #expect(Fixtures.pixel(framed, x: 120, y: 70)[3] == 255)
  }

  @Test func frameRatioShapesTheCanvas() throws {
    let framed = try FrameOps.render(
      Fixtures.image(width: 200, height: 100), recipe: FrameRecipe(padding: 0.05, ratio: .square))
    #expect(framed.width == framed.height)
    #expect(
      try FrameOps.render(Fixtures.image(width: 100, height: 100), recipe: FrameRecipe(ratio: .landscape16x9))
        .width > 100)
  }

  @Test func collageLaysOutAGridInNameOrder() async throws {
    let dir = try TempDir()
    let urls = try ["c.png", "a.png", "b.png"].map {
      try Fixtures.writeImage(to: dir.file($0), type: "public.png", width: 40, height: 40)
    }
    let recipe = CollageRecipe(spacing: 0.02, width: 1000)
    #expect(recipe.columnCount(for: 3) == 2)
    #expect(recipe.columnCount(for: 9) == 3)
    let result = await Processor(settings: AppSettings()).run(
      .collage(recipe), on: try load(urls[0], urls[1], urls[2]))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "Collage.png")
    let (w, h) = pixelSize(out)
    #expect(w == 1000)
    // Square cells, two rows: height ≈ width for a 2×2 grid with even gaps.
    #expect(abs(h - 1000) <= 2)
  }

  @Test func collageNeedsTwoImages() throws {
    let dir = try TempDir()
    let files = try load(Fixtures.writeImage(to: dir.file("a.png"), type: "public.png"))
    #expect(
      Processor.validate(.collage(CollageRecipe()), files: files)
        == "Drop at least two images to make a collage.")
  }

  @Test func backgroundImageFillsBehindTheSubject() throws {
    let dir = try TempDir()
    let photo = try Fixtures.writeImage(to: dir.file("bg.png"), type: "public.png", width: 10, height: 10)
    let ctx = CGContext(
      data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let subject = ctx.makeImage()!  // fully transparent "subject"
    let out = try BackgroundOps.composite(subject: subject, over: .image(path: photo.path))
    #expect(Fixtures.pixel(out, x: 10, y: 10) == Fixtures.pixel(Fixtures.image(), x: 1, y: 1))
  }

  @Test func readsQRCodes() async throws {
    let dir = try TempDir()
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data("https://example.com/fdu".utf8), forKey: "inputMessage")
    let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let cg = CIContext().createCGImage(qr, from: qr.extent.insetBy(dx: -40, dy: -40))!
    let url = try Fixtures.writeCGImage(cg, to: dir.file("qr.png"))
    let result = await Processor(settings: AppSettings()).run(.readQRCodes, on: try load(url))
    #expect(result.notes == ["https://example.com/fdu"])
    #expect(result.succeeded)

    let plain = try Fixtures.writeImage(to: dir.file("plain.png"), type: "public.png")
    let none = await Processor(settings: AppSettings()).run(.readQRCodes, on: try load(plain))
    #expect(none.failures.first?.message == "No QR codes found.")
  }
}

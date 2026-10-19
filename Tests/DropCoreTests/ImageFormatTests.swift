import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import DropCore

@Suite struct ExtraImageFormatTests {
  private func load(_ url: URL) throws -> DroppedFile { try DroppedFile.load(url) }

  @Test func recognisesReadOnlyFormats() async {
    for ext in ["CR2", "cr3", "nef", "arw", "dng", "raf", "orf"] {
      #expect(FileKind(url: URL(fileURLWithPath: "/a.\(ext)")) == .image(.raw), "\(ext)")
    }
    let expected: [String: ImageFormat] = [
      "psd": .psd, "icns": .icns, "ico": .ico, "jp2": .jpeg2000, "j2k": .jpeg2000, "exr": .exr, "tga": .tga,
      "ppm": .netpbm, "pbm": .netpbm, "hdr": .hdr,
    ]
    for (ext, format) in expected {
      #expect(ImageFormat(fileExtension: ext) == format, "\(ext)")
    }
    for format in [ImageFormat.raw, .psd, .netpbm, .hdr] {
      #expect(!format.isWritable && !format.isImageIOWritable)
    }
    for format in [ImageFormat.ico, .icns, .jpeg2000, .tga, .exr] {
      #expect(format.isWritable)
    }
  }

  @Test(arguments: [
    ("psd", "com.adobe.photoshop-image"), ("tga", "com.truevision.tga-image"),
    ("exr", "com.ilm.openexr-image"), ("jp2", "public.jpeg-2000"), ("ppm", "public.pbm"),
  ])
  func readsGeneratedInputs(ext: String, uti: String) async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("in.\(ext)"), type: uti, width: 60, height: 30)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convert(.png, quality: 1), on: [try load(src)])
    #expect(result.failures.isEmpty, "\(result.failures)")
    let image = try ImageOps.loadOriented(try #require(result.outputs.first))
    #expect(image.width == 60 && image.height == 30)
  }

  @Test func readsRadianceHDR() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeHDR(to: dir.file("sky.hdr"))
    #expect(try load(src).kind == .image(.hdr))
    let out = dir.file("sky.png")
    try await ImageConvert.convert(src, to: .png, quality: 1, destination: out)
    #expect(try ImageOps.loadOriented(out).width == 4)
  }

  @Test(arguments: [ImageFormat.jpeg2000, .tga, .exr])
  func writesImageIOFormats(format: ImageFormat) async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png", width: 50, height: 20)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convert(format, quality: 0.8), on: [try load(src)])
    let out = try #require(result.outputs.first)
    #expect(out.pathExtension == format.fileExtension)
    #expect(Fixtures.typeIdentifier(of: out) == format.typeIdentifier)
    #expect(try ImageOps.loadOriented(out).width == 50)
  }

  @Test func writesIconsAtStandardSizes() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("logo.png"), type: "public.png", width: 300, height: 200)
    let ico = dir.file("logo.ico")
    try await ImageConvert.convert(src, to: .ico, quality: 1, options: FormatSettings(), destination: ico)
    let icoSource = try #require(CGImageSourceCreateWithURL(ico as CFURL, nil))
    #expect(CGImageSourceGetType(icoSource) as String? == "com.microsoft.ico")
    // 16…256: every standard size up to the source's 300 px.
    #expect(CGImageSourceGetCount(icoSource) == ImageToolOps.icoSizes.count)
    let biggest = try #require(
      CGImageSourceCreateImageAtIndex(icoSource, CGImageSourceGetCount(icoSource) - 1, nil))
    #expect(biggest.width == biggest.height)

    let icns = dir.file("logo.icns")
    try await ImageConvert.convert(src, to: .icns, quality: 1, options: FormatSettings(), destination: icns)
    #expect(Fixtures.typeIdentifier(of: icns) == "com.apple.icns")
    // Icons read back as images, so they can be converted again.
    #expect(try load(icns).kind == .image(.icns))
    #expect(try ImageOps.loadOriented(icns).width >= 256)
  }

  @Test func resizeSpecComputesSizes() async {
    #expect(ResizeSpec.maxEdge(100).size(width: 400, height: 200) == (100, 50))
    #expect(ResizeSpec.maxEdge(800).size(width: 200, height: 400) == (400, 800))
    #expect(ResizeSpec.percent(50).size(width: 101, height: 3) == (51, 2))
    #expect(ResizeSpec.percent(0).size(width: 1000, height: 10) == (10, 1))
  }

  @Test func resizesAndKeepsFormat() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("photo.jpg"), width: 400, height: 100)
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.resize(.maxEdge(200)), on: [try load(src)])
    let out = try #require(result.outputs.first)
    #expect(out.lastPathComponent == "photo resized.jpg")
    let image = try ImageOps.loadOriented(out)
    #expect(image.width == 200 && image.height == 50)
  }

  @Test func grayscaleRemovesColour() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("orange.png"), type: "public.png")
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.grayscale, on: [try load(src)])
    let out = try #require(result.outputs.first)
    #expect(out.lastPathComponent == "orange grayscale.png")
    let px = Fixtures.pixel(try ImageOps.loadOriented(out), x: 5, y: 5)
    #expect(abs(px[0] - px[1]) <= 2 && abs(px[1] - px[2]) <= 2, "\(px)")
  }

  @Test func resizeAndGrayscaleNeedImages() async throws {
    let dir = try TempDir()
    let pdf = try load(Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1))
    #expect(Processor.validate(.resize(.percent(50)), files: [pdf]) != nil)
    #expect(Processor.validate(.grayscale, files: [pdf]) != nil)
  }

  @Test func floatPixelsAreWrittenAsEightBit() async throws {
    let dir = try TempDir()
    let hdr = try load(Fixtures.writeHDR(to: dir.file("sky.hdr")))
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.convert(.jpeg2000, quality: 0.8), on: [hdr])
    #expect(result.failures.isEmpty, "\(result.failures)")
    #expect(Fixtures.typeIdentifier(of: try #require(result.outputs.first)) == "public.jpeg-2000")
  }

  @Test func editsKeepTGAAndEXR() async throws {
    let dir = try TempDir()
    for (name, uti) in [("t.tga", "com.truevision.tga-image"), ("e.exr", "com.ilm.openexr-image")] {
      let src = try load(Fixtures.writeImage(to: dir.file(name), type: uti, width: 80, height: 40))
      let crop = EditRecipe(crop: NormRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
      let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
        .run(.edit(crop), on: [src])
      #expect(result.failures.isEmpty, "\(name): \(result.failures)")
      #expect(try ImageOps.loadOriented(try #require(result.outputs.first)).width == 40)
    }
  }

  @Test func metadataEditingNeedsAWritableFormat() async throws {
    let dir = try TempDir()
    let tga = try load(Fixtures.writeImage(to: dir.file("t.tga"), type: "com.truevision.tga-image"))
    let jpg = try load(Fixtures.writeImage(to: dir.file("p.jpg")))
    let edit = [MetadataEdit(tag: "XMP-dc:Title", value: "x")]
    #expect(
      Processor.validate(.editMetadata(edit), files: [tga])?.contains("can't hold photo metadata") == true)
    #expect(Processor.validate(.editMetadata(edit), files: [jpg]) == nil)
  }
}

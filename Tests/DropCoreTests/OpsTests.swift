import Foundation
import ImageIO
import Testing

@testable import DropCore

@Suite struct ImageOpsTests {
  @Test(arguments: ImageFormat.allCases.filter(\.isImageIOWritable))
  func convertsPNGToEachFormat(format: ImageFormat) throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("in.png"), type: "public.png")
    let out = dir.file("out.\(format.fileExtension)")
    try ImageOps.convert(src, to: format, quality: 0.8, destination: out)
    #expect(Fixtures.typeIdentifier(of: out) == format.typeIdentifier)
    let props = Fixtures.properties(of: out)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 40)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 20)
  }

  @Test func lowerQualityGivesSmallerJPEG() throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("in.png"), type: "public.png", width: 400, height: 400)
    let high = dir.file("high.jpg")
    let low = dir.file("low.jpg")
    try ImageOps.convert(src, to: .jpeg, quality: 1.0, destination: high)
    try ImageOps.convert(src, to: .jpeg, quality: 0.1, destination: low)
    let size = { (u: URL) in try FileManager.default.attributesOfItem(atPath: u.path)[.size] as! Int }
    #expect(try size(low) < size(high))
  }

  @Test func convertRejectsNonImage() throws {
    let dir = try TempDir()
    let fake = try dir.touch("fake.png", contents: "not an image")
    #expect(throws: DropError.readFailed("fake.png")) {
      try ImageOps.convert(fake, to: .jpeg, quality: 0.8, destination: dir.file("o.jpg"))
    }
  }

  @Test func readsMetadataAndLocation() throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("m.jpg"), withMetadata: true)
    let meta = try ImageOps.metadata(of: src)
    #expect(meta["TIFF: Make"] == "TestCam")
    #expect(try ImageOps.hasLocation(src))
  }

  @Test func stripRemovesExifGpsAndTiff() throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("m.jpg"), withMetadata: true)
    let out = dir.file("clean.jpg")
    try ImageOps.stripMetadata(src, destination: out)

    #expect(try !ImageOps.hasLocation(out))
    let meta = try ImageOps.metadata(of: out)
    #expect(meta["TIFF: Make"] == nil)
    #expect(meta["TIFF: Artist"] == nil)
    #expect(meta["Exif: UserComment"] == nil)
    #expect(meta["Exif: DateTimeOriginal"] == nil)
    #expect(Fixtures.typeIdentifier(of: out) == "public.jpeg")
    // The original is untouched.
    #expect(try ImageOps.hasLocation(src))
  }
}

@Suite struct PDFOpsTests {
  @Test func mergeSumsPagesInOrder() throws {
    let dir = try TempDir()
    let a = try Fixtures.writePDF(to: dir.file("a.pdf"), pages: 2)
    let b = try Fixtures.writePDF(to: dir.file("b.pdf"), pages: 3)
    let out = dir.file("m.pdf")
    try PDFOps.merge([a, b], destination: out)
    #expect(PDFOps.pageCount(of: out) == 5)
  }

  @Test func mergeRejectsBrokenPDF() throws {
    let dir = try TempDir()
    let a = try Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1)
    let bad = try dir.touch("bad.pdf", contents: "nope")
    #expect(throws: DropError.readFailed("bad.pdf")) {
      try PDFOps.merge([a, bad], destination: dir.file("m.pdf"))
    }
  }

  @Test func imagesToPDFOnePagePerImage() throws {
    let dir = try TempDir()
    let a = try Fixtures.writeImage(to: dir.file("a.jpg"), width: 30, height: 10)
    let b = try Fixtures.writeImage(to: dir.file("b.png"), type: "public.png", width: 50, height: 60)
    let out = dir.file("i.pdf")
    try PDFOps.imagesToPDF([a, b], destination: out)
    #expect(PDFOps.pageCount(of: out) == 2)
  }

  @Test func imagesToPDFCleansUpOnFailure() throws {
    let dir = try TempDir()
    let bad = try dir.touch("bad.jpg", contents: "nope")
    let out = dir.file("i.pdf")
    #expect(throws: DropError.readFailed("bad.jpg")) { try PDFOps.imagesToPDF([bad], destination: out) }
    #expect(!FileManager.default.fileExists(atPath: out.path))
  }
}

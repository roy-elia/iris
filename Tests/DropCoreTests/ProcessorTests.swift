import Foundation
import Testing

@testable import DropCore

@Suite struct ProcessorTests {
  private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

  @Test func validationMessages() throws {
    let dir = try TempDir()
    let img = try load(Fixtures.writeImage(to: dir.file("a.jpg")))
    let pdf = try load(Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1))

    #expect(Processor.validate(.stripMetadata, files: []) == "Drop some files first.")
    #expect(Processor.validate(.convert(.png, quality: 1), files: pdf)?.contains("images only") == true)
    #expect(Processor.validate(.mergePDFs, files: img) == "Merge PDFs works on PDF files only.")
    #expect(Processor.validate(.mergePDFs, files: pdf) == "Drop at least two PDFs to merge.")
    #expect(Processor.validate(.imagesToPDF, files: img) == nil)
  }

  @Test func invalidRunReportsFailureAndWritesNothing() throws {
    let dir = try TempDir()
    let pdf = try load(Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1))
    let result = Processor(settings: AppSettings()).run(.stripMetadata, on: pdf)
    #expect(!result.succeeded)
    #expect(result.outputs.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.path) == ["a.pdf"])
  }

  @Test func convertWritesNextToSourceWithoutOverwriting() throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("photo.png"), type: "public.png")
    try dir.touch("photo.jpg", contents: "existing")  // must survive
    let result = Processor(settings: AppSettings()).run(.convert(.jpeg, quality: 0.8), on: try load(src))

    #expect(result.succeeded)
    #expect(result.outputs.map(\.lastPathComponent) == ["photo (1).jpg"])
    #expect(try String(contentsOf: dir.file("photo.jpg"), encoding: .utf8) == "existing")
  }

  @Test func sameNamesInOneRunGetDistinctOutputs() throws {
    let dir = try TempDir()
    try FileManager.default.createDirectory(at: dir.file("x"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.file("y"), withIntermediateDirectories: true)
    let a = try Fixtures.writeImage(to: dir.file("x/pic.png"), type: "public.png")
    let b = try Fixtures.writeImage(to: dir.file("y/pic.png"), type: "public.png")
    let out = dir.file("out")
    let settings = AppSettings(outputLocation: .folder(out))
    let result = Processor(settings: settings).run(.convert(.tiff, quality: 1), on: try load(a, b))
    #expect(result.outputs.map(\.lastPathComponent) == ["pic.tiff", "pic (1).tiff"])
    #expect(result.outputs.allSatisfy { $0.deletingLastPathComponent().path == out.path })
  }

  @Test func keepsGoingPastABadFile() throws {
    let dir = try TempDir()
    let good = try Fixtures.writeImage(to: dir.file("good.jpg"))
    let bad = try dir.touch("bad.jpg", contents: "nope")
    let result = Processor(settings: AppSettings()).run(.convert(.png, quality: 1), on: try load(good, bad))
    #expect(result.outputs.map(\.lastPathComponent) == ["good.png"])
    #expect(result.failures == [.init(file: "bad.jpg", message: "bad.jpg could not be read.")])

    let entry = result.historyEntry(for: .convert(.png, quality: 1), inputCount: 2)
    #expect(entry.operation == "Convert to PNG")
    #expect(entry.errors == ["bad.jpg: bad.jpg could not be read."])
    #expect(!entry.succeeded)
  }

  @Test func stripNamesOutputAndKeepsOriginal() throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("trip.jpg"), withMetadata: true)
    let result = Processor(settings: AppSettings()).run(.stripMetadata, on: try load(src))
    #expect(result.outputs.map(\.lastPathComponent) == ["trip no-metadata.jpg"])
    #expect(try !ImageOps.hasLocation(result.outputs[0]))
    #expect(try ImageOps.hasLocation(src))
  }

  @Test func mergeAndImagesToPDFNames() throws {
    let dir = try TempDir()
    let a = try Fixtures.writePDF(to: dir.file("a.pdf"), pages: 1)
    let b = try Fixtures.writePDF(to: dir.file("b.pdf"), pages: 2)
    let merged = Processor(settings: AppSettings()).run(.mergePDFs, on: try load(a, b))
    #expect(merged.outputs.map(\.lastPathComponent) == ["Merged.pdf"])
    #expect(PDFOps.pageCount(of: merged.outputs[0]) == 3)

    let i1 = try Fixtures.writeImage(to: dir.file("one.jpg"))
    let i2 = try Fixtures.writeImage(to: dir.file("two.jpg"))
    let single = Processor(settings: AppSettings()).run(.imagesToPDF, on: try load(i1))
    #expect(single.outputs.map(\.lastPathComponent) == ["one.pdf"])
    let multi = Processor(settings: AppSettings()).run(.imagesToPDF, on: try load(i1, i2))
    #expect(multi.outputs.map(\.lastPathComponent) == ["Images.pdf"])
    #expect(PDFOps.pageCount(of: multi.outputs[0]) == 2)
  }
}

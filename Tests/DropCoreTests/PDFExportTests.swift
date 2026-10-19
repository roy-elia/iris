import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing

@testable import DropCore

@Suite struct PDFExportTests {
  private func run(_ op: FileOperation, _ url: URL, in dir: TempDir) async throws -> OperationResult {
    await Processor(settings: AppSettings(outputLocation: .folder(dir.url))).run(
      op, on: [try DroppedFile.load(url)])
  }

  @Test func parsesPageRanges() async throws {
    #expect(try PDFSplit.ranges("1-3, 7").groups(pageCount: 9) == [[0, 1, 2], [6]])
    #expect(try PDFSplit.ranges("8-").groups(pageCount: 9) == [[7, 8]])
    #expect(try PDFSplit.everyPage.groups(pageCount: 3) == [[0], [1], [2]])
    for bad in ["", "0", "3-1", "a", "1-2-3", "10"] {
      #expect(throws: DropError.self, "\(bad)") { try PDFSplit.ranges(bad).groups(pageCount: 9) }
    }
    #expect(PDFSplit.label([2]) == "page 3" && PDFSplit.label([0, 1, 2]) == "pages 1-3")
  }

  @Test func splitsEveryPage() async throws {
    let dir = try TempDir()
    let pdf = try Fixtures.writePDF(to: dir.file("deck.pdf"), pages: 3)
    let result = try await run(.splitPDF(.everyPage), pdf, in: dir)
    #expect(
      result.outputs.map(\.lastPathComponent) == ["deck page 1.pdf", "deck page 2.pdf", "deck page 3.pdf"])
    #expect(result.outputs.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 })
  }

  @Test func splitsRanges() async throws {
    let dir = try TempDir()
    let pdf = try Fixtures.writePDF(to: dir.file("deck.pdf"), pages: 5)
    let result = try await run(.splitPDF(.ranges("1-3,5")), pdf, in: dir)
    #expect(result.outputs.map(\.lastPathComponent) == ["deck pages 1-3.pdf", "deck page 5.pdf"])
    #expect(result.outputs.map { PDFDocument(url: $0)?.pageCount } == [3, 1])
    let bad = try await run(.splitPDF(.ranges("4-9")), pdf, in: dir)
    #expect(bad.outputs.isEmpty && bad.failures.first?.message.contains("past the end") == true)
  }

  @Test func savesMultiPageTIFF() async throws {
    let dir = try TempDir()
    let pdf = try Fixtures.writePDF(to: dir.file("scan.pdf"), pages: 3)
    let out = try #require(try await run(.pdfToTIFF, pdf, in: dir).outputs.first)
    #expect(out.lastPathComponent == "scan.tiff")
    let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == "public.tiff")
    #expect(CGImageSourceGetCount(source) == 3)
    // 200 × 100 pt pages at 144 dpi.
    #expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width == 400)
  }

  @Test func savesComicBookZip() async throws {
    let dir = try TempDir()
    let pdf = try Fixtures.writePDF(to: dir.file("comic.pdf"), pages: 2)
    let out = try #require(try await run(.pdfToCBZ, pdf, in: dir).outputs.first)
    #expect(out.lastPathComponent == "comic.cbz")
    let listing = try await SystemProcess.run("/usr/bin/zipinfo", ["-1", out.path])
    #expect(
      String(decoding: listing.stdout, as: UTF8.self).split(separator: "\n").sorted() == [
        "001.jpg", "002.jpg",
      ])
  }

  @Test func refusesNonPDFs() async throws {
    let dir = try TempDir()
    let png = try DroppedFile.load(Fixtures.writeImage(to: dir.file("a.png"), type: "public.png"))
    for op in [FileOperation.pdfToTIFF, .pdfToCBZ, .splitPDF(.everyPage)] {
      #expect(Processor.validate(op, files: [png])?.contains("PDFs only") == true)
    }
  }
}

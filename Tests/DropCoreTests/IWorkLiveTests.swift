import Foundation
import PDFKit
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// These drive Keynote and Numbers, so they run only with FDU_TEST_IWORK=1 and the app
/// installed: `FDU_TEST_IWORK=1 scripts/test.sh --filter IWorkLiveTests`.
private let liveIWork = ProcessInfo.processInfo.environment["FDU_TEST_IWORK"] == "1"

private func osascript(_ lines: [String], _ args: [String]) async throws {
  try await SystemProcess.run("/usr/bin/osascript", lines.flatMap { ["-e", $0] } + args, timeout: 180)
}

@Suite(.serialized) struct IWorkLiveTests {
  /// A three-slide deck made by Keynote, saved as PDF and as one PNG per slide.
  @Test(.enabled(if: liveIWork && IWorkApp.keynote.isInstalled)) func keynoteExportsEverySlide() async throws
  {
    let dir = try TempDir()
    let deck = dir.file("Talk.key")
    try await osascript(
      [
        "on run argv",
        "tell application id \"\(IWorkApp.keynote.bundleID)\"",
        "set d to make new document",
        "tell d",
        "make new slide",
        "make new slide",
        "end tell",
        "save d in (POSIX file (item 1 of argv))",
        "close d saving no",
        "end tell",
        "end run",
      ], [deck.path])
    let pdf = await Processor(settings: AppSettings()).run(.convertDocument(.pdf), on: try load(deck))
    #expect(PDFDocument(url: try #require(pdf.outputs.first, "\(pdf.failures)"))?.pageCount == 3)
    let slides = await Processor(settings: AppSettings()).run(.pdfToImages(.png), on: try load(deck))
    #expect(slides.outputs.count == 3, "\(slides.failures)")
  }

  /// A Numbers document with two cells set, saved as CSV through Numbers' Excel export.
  @Test(.enabled(if: liveIWork && IWorkApp.numbers.isInstalled)) func numbersSheetsBecomeCSV() async throws {
    let dir = try TempDir()
    let book = dir.file("Ledger.numbers")
    try await osascript(
      [
        "on run argv",
        "tell application id \"\(IWorkApp.numbers.bundleID)\"",
        "set d to make new document",
        "tell table 1 of sheet 1 of d",
        "set value of cell \"A1\" to \"Item\"",
        "set value of cell \"B1\" to \"Cost\"",
        "set value of cell \"A2\" to \"Paper\"",
        "set value of cell \"B2\" to 12",
        "end tell",
        "save d in (POSIX file (item 1 of argv))",
        "close d saving no",
        "end tell",
        "end run",
      ], [book.path])
    let files = try load(book)
    #expect(Processor.validate(.sheetsToCSV, files: files) == nil)
    let result = await Processor(settings: AppSettings()).run(.sheetsToCSV, on: files)
    let out = try #require(result.outputs.first, "\(result.failures)")
    let text = try String(contentsOf: out, encoding: .utf8)
    #expect(text.contains("Item,Cost") && text.contains("Paper,12"))
  }
}

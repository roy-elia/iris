import Foundation
import PDFKit
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// Opening PowerPoint in every test run would be intrusive, so the live test runs only
/// with FDU_TEST_POWERPOINT=1 (and PowerPoint installed, Keynote not).
private let livePowerPoint =
  ProcessInfo.processInfo.environment["FDU_TEST_POWERPOINT"] == "1" && PowerPoint.isInstalled
  && !IWorkApp.keynote.isInstalled

@Suite struct PowerPointTests {
  @Test func exportScriptSavesAsPDFAndCloses() {
    let script = PowerPoint.exportScript().joined(separator: "\n")
    #expect(script.contains("tell application id \"com.microsoft.Powerpoint\""))
    #expect(script.contains("as save as PDF"))
    #expect(script.contains("close active presentation saving no"))
    #expect(OfficeFormat.pptx.powerPointExports && OfficeFormat.ppt.powerPointExports)
    #expect(!OfficeFormat.key.powerPointExports && !OfficeFormat.xlsx.powerPointExports)
  }

  @Test func workFolderIsInsidePowerPointsContainer() throws {
    let folder = try PowerPoint.workFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(folder.path.contains("/Library/Containers/com.microsoft.Powerpoint/Data/tmp/"))
  }

  /// Makes a three-slide deck with PowerPoint itself, then saves every slide as PNG.
  @Test(.enabled(if: livePowerPoint)) func savesEverySlideThroughPowerPoint() async throws {
    let folder = try PowerPoint.workFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let made = folder.appendingPathComponent("made.pptx")
    let script = [
      "on run argv",
      "tell application id \"\(PowerPoint.bundleID)\"",
      "set p to make new presentation",
      "repeat 3 times",
      "make new slide at end of p with properties {layout:slide layout title slide}",
      "end repeat",
      "save p in (POSIX file (item 1 of argv)) as save as Open XML presentation",
      "close active presentation saving no",
      "end tell",
      "end run",
    ]
    try await SystemProcess.run(
      "/usr/bin/osascript", script.flatMap { ["-e", $0] } + [made.path], timeout: 120)
    let dir = try TempDir()
    let deck = dir.file("Pitch.pptx")
    try FileManager.default.copyItem(at: made, to: deck)

    let pdf = await Processor(settings: AppSettings()).run(.convertDocument(.pdf), on: try load(deck))
    #expect(PDFDocument(url: try #require(pdf.outputs.first, "\(pdf.failures)"))?.pageCount == 3)
    let slides = await Processor(settings: AppSettings()).run(.pdfToImages(.png), on: try load(deck))
    #expect(
      slides.outputs.map(\.lastPathComponent) == [
        "Pitch slide 1.png", "Pitch slide 2.png", "Pitch slide 3.png",
      ])
  }
}

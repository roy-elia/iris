import Foundation
import ImageIO
import Testing

@testable import DropCore

/// One test per acceptance criterion in SETUP.md. A1 (build/test/lint) and A10 (share
/// picker opens) are checked by running the tools and the app, not here.
@Suite("Acceptance") struct AcceptanceTests {
  private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  private func drop(_ urls: [URL]) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

  @Test("A2: the app bundle is menu-bar only (LSUIElement)")
  func a2MenuBarOnly() async throws {
    let script = try String(contentsOf: repoRoot.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
    let start = try #require(script.range(of: "<?xml"))
    let end = try #require(script.range(of: "</plist>"))
    let plistData = Data(script[start.lowerBound..<end.upperBound].utf8)
    let plist = try #require(
      try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
    #expect(plist["LSUIElement"] as? Bool == true)
    #expect(plist["CFBundleExecutable"] as? String == "FileDropUtility")
  }

  @Test("A3: dropped images convert to each format with readable output")
  func a3Convert() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("pic.jpg"), width: 64, height: 32)
    for format in ImageFormat.writable {
      let result = await AppSettings().processor.run(.convert(format, quality: 0.7), on: try drop([src]))
      #expect(result.succeeded, "\(format)")
      let out = try #require(result.outputs.first, "\(result.failures)")
      #expect(out.pathExtension == format.fileExtension)
      #expect(Fixtures.typeIdentifier(of: out) == format.typeIdentifier)
      let props = Fixtures.properties(of: out)
      if format.isIcon {
        // Icons hold square images at standard sizes.
        #expect(props[kCGImagePropertyPixelWidth] as? Int == props[kCGImagePropertyPixelHeight] as? Int)
      } else {
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 64)
      }
    }
  }

  @Test("A4: stripping metadata removes EXIF, GPS and camera fields")
  func a4Strip() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("trip.jpg"), withMetadata: true)
    let result = await AppSettings().processor.run(.stripMetadata, on: try drop([src]))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let meta = try ImageOps.metadata(of: out)
    #expect(!meta.keys.contains { $0.hasPrefix("GPS:") })
    #expect(meta["TIFF: Make"] == nil)
    #expect(meta["Exif: UserComment"] == nil)
  }

  @Test("A5: PDFs merge in order and images become one page each")
  func a5PDF() async throws {
    let dir = try TempDir()
    let pdfs = [
      try Fixtures.writePDF(to: dir.file("1.pdf"), pages: 1),
      try Fixtures.writePDF(to: dir.file("2.pdf"), pages: 4),
    ]
    let merged = await AppSettings().processor.run(.mergePDFs, on: try drop(pdfs))
    #expect(PDFOps.pageCount(of: try #require(merged.outputs.first)) == 5)

    let images = try (1...3).map { try Fixtures.writeImage(to: dir.file("img\($0).png"), type: "public.png") }
    let built = await AppSettings().processor.run(.imagesToPDF, on: try drop(images))
    #expect(PDFOps.pageCount(of: try #require(built.outputs.first)) == 3)
  }

  @Test("A6: outputs never overwrite existing files")
  func a6NoOverwrite() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("a.png"), type: "public.png")
    let existing = try dir.touch("a.jpg", contents: "keep me")
    let processor = AppSettings().processor
    let first = await processor.run(.convert(.jpeg, quality: 0.8), on: try drop([src]))
    let second = await processor.run(.convert(.jpeg, quality: 0.8), on: try drop([src]))
    #expect(first.outputs.map(\.lastPathComponent) == ["a (1).jpg"])
    #expect(second.outputs.map(\.lastPathComponent) == ["a (2).jpg"])
    #expect(try String(contentsOf: existing, encoding: .utf8) == "keep me")
  }

  @Test("A7: unsupported or broken files give a message, not a crash")
  func a7Errors() async throws {
    let dir = try TempDir()
    let doc = try dir.touch("report.xyz")
    #expect(throws: DropError.unsupportedFile("report.xyz")) { try DroppedFile.load(doc) }

    let broken = try dir.touch("broken.png", contents: "not really")
    let result = await AppSettings().processor.run(.convert(.jpeg, quality: 0.8), on: try drop([broken]))
    #expect(result.outputs.isEmpty)
    #expect(result.failures.first?.message == "broken.png could not be read.")
  }

  @Test("A8: settings persist across restarts")
  func a8Settings() async throws {
    let dir = try TempDir()
    let url = dir.file("settings.json")
    var settings = SettingsStore(fileURL: url).load()
    settings.defaultFormat = .heic
    settings.quality = 0.4
    settings.outputLocation = .folder(dir.file("out"))
    try SettingsStore(fileURL: url).save(settings)
    // A new store stands in for a relaunch.
    #expect(SettingsStore(fileURL: url).load() == settings)
  }

  @Test("A9: history keeps the last 50 operations across restarts")
  func a9History() async throws {
    let dir = try TempDir()
    let url = dir.file("history.json")
    let src = try Fixtures.writeImage(to: dir.file("h.png"), type: "public.png")
    let files = try drop([src])
    for _ in 0..<52 {
      let result = await AppSettings(outputLocation: .folder(dir.file("out"))).processor.run(
        .stripMetadata, on: files)
      try HistoryStore(fileURL: url).append(result.historyEntry(for: .stripMetadata, inputCount: 1))
    }
    let entries = HistoryStore(fileURL: url).load()
    #expect(entries.count == 50)
    #expect(entries.allSatisfy { $0.operation == "Strip metadata" && $0.succeeded })
  }
}

extension AppSettings {
  fileprivate var processor: Processor { Processor(settings: self) }
}

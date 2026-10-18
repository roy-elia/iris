import Foundation
import Testing

@testable import DropCore

@Suite struct ImageFormatTests {
  @Test(arguments: [
    ("png", ImageFormat.png), ("PNG", .png), ("jpg", .jpeg), ("jpeg", .jpeg),
    ("heic", .heic), ("heif", .heic), ("tif", .tiff), ("TIFF", .tiff),
  ])
  func recognisesExtensions(ext: String, expected: ImageFormat) {
    #expect(ImageFormat(fileExtension: ext) == expected)
  }

  @Test func rejectsUnknownExtensions() {
    #expect(ImageFormat(fileExtension: "gif") == nil)
    #expect(ImageFormat(fileExtension: "") == nil)
  }

  @Test func onlyLossyFormatsUseQuality() {
    #expect(ImageFormat.allCases.filter(\.usesQuality) == [.jpeg, .heic])
  }
}

@Suite struct FileKindTests {
  @Test func classifiesByExtension() {
    #expect(FileKind(url: URL(fileURLWithPath: "/a/b.jpg")) == .image(.jpeg))
    #expect(FileKind(url: URL(fileURLWithPath: "/a/b.PDF")) == .pdf)
    #expect(FileKind(url: URL(fileURLWithPath: "/a/b.docx")) == .unsupported)
    #expect(FileKind(url: URL(fileURLWithPath: "/a/noext")) == .unsupported)
  }
}

@Suite struct DroppedFileTests {
  @Test func loadsKindAndSize() throws {
    let dir = try TempDir()
    let url = try dir.touch("photo.png", contents: "12345")
    let file = try DroppedFile.load(url)
    #expect(file.kind == .image(.png))
    #expect(file.byteSize == 5)
    #expect(file.name == "photo.png")
  }

  @Test func rejectsMissingFile() throws {
    let dir = try TempDir()
    #expect(throws: DropError.fileNotFound("gone.png")) {
      try DroppedFile.load(dir.file("gone.png"))
    }
  }

  @Test func rejectsUnsupportedTypeAndFolders() throws {
    let dir = try TempDir()
    let doc = try dir.touch("notes.docx")
    #expect(throws: DropError.unsupportedFile("notes.docx")) { try DroppedFile.load(doc) }

    let folder = dir.file("folder.png")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(throws: DropError.unsupportedFile("folder.png")) { try DroppedFile.load(folder) }
  }

  @Test func errorsHaveUserFacingMessages() {
    #expect(
      DropError.unsupportedFile("a.docx").localizedDescription == "a.docx is not a supported file type.")
  }
}

@Suite struct SettingsTests {
  @Test func clampsQuality() {
    #expect(AppSettings(quality: 5).quality == 1.0)
    #expect(AppSettings(quality: -1).quality == 0.1)
    #expect(AppSettings(quality: .nan).quality == 0.85)
    var s = AppSettings()
    s.quality = 0
    #expect(s.quality == 0.1)
  }

  @Test func roundTripsThroughJSON() throws {
    let original = AppSettings(
      defaultFormat: .heic, quality: 0.5,
      outputLocation: .folder(URL(fileURLWithPath: "/tmp/out")), launchAtLogin: true)
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == original)
  }

  @Test func fillsMissingOrBadFieldsWithDefaults() throws {
    let json = Data(#"{"defaultFormat":"bmp","quality":42}"#.utf8)
    let s = try JSONDecoder().decode(AppSettings.self, from: json)
    #expect(s.defaultFormat == .png)
    #expect(s.quality == 1.0)
    #expect(s.outputLocation == .nextToSource)
    #expect(s.launchAtLogin == false)
  }
}

@Suite struct HistoryEntryTests {
  @Test func succeededNeedsOutputsAndNoErrors() {
    #expect(HistoryEntry(operation: "x", inputCount: 1, outputs: ["a"], errors: []).succeeded)
    #expect(!HistoryEntry(operation: "x", inputCount: 1, outputs: [], errors: []).succeeded)
    #expect(!HistoryEntry(operation: "x", inputCount: 2, outputs: ["a"], errors: ["b"]).succeeded)
  }
}

@Suite struct OperationTests {
  @Test func summaries() {
    #expect(FileOperation.convert(.jpeg, quality: 0.8).summary == "Convert to JPEG")
    #expect(FileOperation.mergePDFs.summary == "Merge PDFs")
  }
}

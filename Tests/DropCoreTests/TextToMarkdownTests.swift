import Foundation
import Testing

@testable import DropCore

@Suite struct TextToMarkdownTests {
  private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2md-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func keepsTextAsCopiedWithNormalisedEndings() {
    let out = TextToMarkdown.contents(of: "\u{FEFF}# Hi\r\n\r\n- a\r- b\n\n\n")
    #expect(out == "# Hi\n\n- a\n- b\n")
  }

  @Test func namesFileFromFirstLine() {
    #expect(TextToMarkdown.baseName(for: "\n\n## Plan: Q3 / launch?\nbody") == "Plan Q3 launch")
    #expect(TextToMarkdown.baseName(for: String(repeating: "word ", count: 40)).count <= 48)
  }

  @Test func fallsBackToTimestampName() {
    let name = TextToMarkdown.baseName(for: "***\n", date: Date(timeIntervalSince1970: 0))
    #expect(name.hasPrefix("Pasted text 19"))
    #expect(!name.contains("/") && !name.contains(":"))
  }

  @Test func writesMarkdownFileAndNeverOverwrites() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let first = try TextToMarkdown.write("# Notes\nhello", to: dir)
    let second = try TextToMarkdown.write("# Notes\nagain", to: dir)
    #expect(first.lastPathComponent == "Notes.md")
    #expect(second.lastPathComponent == "Notes (1).md")
    #expect(try String(contentsOf: first, encoding: .utf8) == "# Notes\nhello\n")
    #expect(DocumentFormat(fileExtension: first.pathExtension) == .md)
  }

  @Test func rejectsBlankText() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(throws: TextToMarkdown.Failure.empty) { try TextToMarkdown.write(" \n\t ", to: dir) }
  }

  @Test func destinationUsesChosenFolder() {
    let folder = URL(fileURLWithPath: "/tmp/out")
    #expect(TextToMarkdown.destination(for: .folder(folder)) == folder)
    #expect(TextToMarkdown.destination(for: .nextToSource).lastPathComponent == "Downloads")
  }
}

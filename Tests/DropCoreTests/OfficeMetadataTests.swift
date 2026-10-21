import AppKit
import Foundation
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// Word, Excel and PowerPoint packages: strip removes document properties and people's
/// names; copy carries another file's document properties over.
@Suite struct OfficeMetadataTests {
  private let rels = "http://schemas.openxmlformats.org/package/2006/relationships"

  /// The package-level parts every fixture shares: content types, the root relationships
  /// and filled-in core, app and custom properties.
  private func packageParts(main: String, title: String, author: String) -> [String: String] {
    [
      "[Content_Types].xml": """
      <?xml version="1.0" encoding="UTF-8"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
      <Default Extension="xml" ContentType="application/xml"/>\
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>\
      <Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/>\
      </Types>
      """,
      "_rels/.rels": """
      <?xml version="1.0" encoding="UTF-8"?>
      <Relationships xmlns="\(rels)">\
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="\(main)"/>\
      <Relationship Id="rId2" Type="\(MetadataOps.DocumentPart.core.relationship)" Target="docProps/core.xml"/>\
      <Relationship Id="rId3" Type="\(MetadataOps.DocumentPart.app.relationship)" Target="docProps/app.xml"/>\
      <Relationship Id="rId4" Type="\(MetadataOps.DocumentPart.custom.relationship)" Target="docProps/custom.xml"/>\
      </Relationships>
      """,
      "docProps/core.xml": """
      <cp:coreProperties xmlns:cp="cp" xmlns:dc="http://purl.org/dc/elements/1.1/">\
      <dc:title>\(title)</dc:title><dc:creator>\(author)</dc:creator>\
      <cp:lastModifiedBy>\(author)</cp:lastModifiedBy></cp:coreProperties>
      """,
      "docProps/app.xml":
        "<Properties><Company>Acme Secret Corp</Company><Manager>Mallory</Manager></Properties>",
      "docProps/custom.xml":
        "<Properties><property name=\"Client\"><vt:lpwstr>Project X</vt:lpwstr></property></Properties>",
    ]
  }

  private func docx(_ url: URL, title: String = "Secret plan", author: String = "Alice Smith") async throws
    -> URL
  {
    let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    var parts = packageParts(main: "word/document.xml", title: title, author: author)
    parts["word/document.xml"] = """
      <w:document xmlns:w="\(w)"><w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p>\
      <w:p><w:ins w:id="1" w:author="\(author)" w:date="2024-01-01T00:00:00Z"><w:r><w:t>added</w:t></w:r></w:ins></w:p>\
      </w:body></w:document>
      """
    parts["word/comments.xml"] = """
      <w:comments xmlns:w="\(w)"><w:comment w:id="0" w:author="\(author)" w:initials="AS"><w:p/></w:comment></w:comments>
      """
    parts["word/people.xml"] = """
      <w15:people xmlns:w15="w15"><w15:person w15:author="\(author)">\
      <w15:presenceInfo w15:providerId="AD" w15:userId="alice@example.com"/></w15:person></w15:people>
      """
    parts["word/settings.xml"] = """
      <w:settings xmlns:w="\(w)" xmlns:r="r"><w:attachedTemplate r:id="rId1"/><w:zoom w:percent="100"/></w:settings>
      """
    parts["word/_rels/settings.xml.rels"] = """
      <Relationships xmlns="\(rels)"><Relationship Id="rId1" \
      Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" \
      Target="file:///C:/Users/alice.smith/Templates/Normal.dotm" TargetMode="External"/></Relationships>
      """
    return try await SheetFixtures.zip(parts, to: url)
  }

  private func xlsx(_ url: URL) async throws -> URL {
    var parts = packageParts(main: "xl/workbook.xml", title: "Budget", author: "Bob Jones")
    parts["xl/workbook.xml"] = "<workbook/>"
    parts["xl/comments1.xml"] = "<comments><authors><author>Bob Jones</author></authors></comments>"
    parts["xl/persons/person.xml"] = """
      <personList><person displayName="Bob Jones" id="{1}" userId="bob@example.com" providerId="AD"/></personList>
      """
    var printer = Data("HP LaserJet Bob's Office".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
    printer += Data(repeating: 7, count: 100)
    let url = try await SheetFixtures.zip(parts, to: url)
    // A binary printer-settings part, added beside the XML ones.
    let dir = url.deletingLastPathComponent().appendingPathComponent("printer-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: dir.appendingPathComponent("xl/printerSettings"), withIntermediateDirectories: true)
    try printer.write(to: dir.appendingPathComponent("xl/printerSettings/printerSettings1.bin"))
    try await SystemProcess.run("/usr/bin/zip", ["-q", "-r", url.path, "."], in: dir)
    return url
  }

  private func pptx(_ url: URL) async throws -> URL {
    var parts = packageParts(main: "ppt/presentation.xml", title: "Pitch", author: "Carol White")
    parts["ppt/presentation.xml"] = "<p:presentation xmlns:p=\"p\"/>"
    parts["ppt/commentAuthors.xml"] = """
      <p:cmAuthorLst xmlns:p="p"><p:cmAuthor id="0" name="Carol White" initials="CW" lastIdx="1"/></p:cmAuthorLst>
      """
    parts["ppt/authors.xml"] = """
      <p188:authorLst xmlns:p188="p188"><p188:author id="{1}" name="Carol White" initials="CW" \
      userId="carol@example.com" providerId="AD"/></p188:authorLst>
      """
    return try await SheetFixtures.zip(parts, to: url)
  }

  /// Every entry's name, and the text of every entry, concatenated.
  private func contents(_ url: URL) async throws -> (names: [String], text: String) {
    let names = try await SystemProcess.run("/usr/bin/zipinfo", ["-1", url.path]).stdout
    let text = try await SystemProcess.run("/usr/bin/unzip", ["-p", url.path]).stdout
    return (
      String(decoding: names, as: UTF8.self).split(separator: "\n").map(String.init),
      String(decoding: text.map { $0 == 0 ? 32 : $0 }, as: UTF8.self)
    )
  }

  @Test(arguments: ["docx", "xlsx", "pptx"])
  func stripRemovesPropertiesAndNames(ext: String) async throws {
    let dir = try TempDir()
    let src: URL
    switch ext {
    case "docx": src = try await docx(dir.file("in.docx"))
    case "xlsx": src = try await xlsx(dir.file("in.xlsx"))
    default: src = try await pptx(dir.file("in.pptx"))
    }
    let result = await Processor(settings: AppSettings()).run(.stripAllMetadata, on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let (names, text) = try await contents(out)

    #expect(names.first == "[Content_Types].xml")
    #expect(!names.contains { $0.hasPrefix("docProps/") })
    #expect(!text.contains("docProps/"), "a dangling reference to the deleted properties")
    for secret in [
      "Alice", "Smith", "Bob Jones", "Carol", "Acme", "Mallory", "Project X", "example.com", "AS\"", "CW\"",
      "alice.smith", "attachedTemplate r:id", "presenceInfo",
    ] {
      #expect(!text.contains(secret), "\(secret) left in .\(ext)")
    }
    // The zip's own timestamps say nothing either.
    let listing = String(
      decoding: try await SystemProcess.run("/usr/bin/zipinfo", ["-l", out.path]).stdout, as: UTF8.self)
    #expect(!listing.contains(String(Calendar.current.component(.year, from: Date()))))
    if ext == "xlsx" {
      let printer = try await SystemProcess.run(
        "/usr/bin/unzip", ["-p", out.path, "xl/printerSettings/printerSettings1.bin"]
      ).stdout
      #expect(printer.prefix(64).allSatisfy { $0 == 0 })
      // Only the name goes; the rest of the settings stay as they were.
      #expect(printer.count == 2 * "HP LaserJet Bob's Office".count + 100)
    }
  }

  @Test func strippedWordFileStillOpens() async throws {
    let dir = try TempDir()
    // A real package from AppKit's Word writer.
    let text = NSAttributedString(string: "Quarterly notes")
    let src = dir.file("real.docx")
    try text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [
        .documentType: NSAttributedString.DocumentType.officeOpenXML, .author: "Alice Smith",
      ]
    ).write(to: src)
    let result = await Processor(settings: AppSettings()).run(.stripAllMetadata, on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    var attributes: NSDictionary?
    let reread = try NSAttributedString(url: out, options: [:], documentAttributes: &attributes)
    #expect(reread.string.contains("Quarterly notes"))
    #expect((attributes?[NSAttributedString.DocumentAttributeKey.author] as? String) == nil)
  }

  @Test func copyReplacesPropertiesAcrossOfficeTypes() async throws {
    let dir = try TempDir()
    let src = try await docx(dir.file("src.docx"), title: "Source title", author: "Dana Source")
    let target = try await xlsx(dir.file("target.xlsx"))

    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let (names, text) = try await contents(out)
    #expect(names.contains("docProps/core.xml") && names.contains("docProps/custom.xml"))
    // Word's statistics don't belong in a spreadsheet.
    #expect(!names.contains("docProps/app.xml"))
    #expect(text.contains("Source title") && text.contains("Dana Source") && text.contains("Project X"))
    #expect(!text.contains("Budget"))
    #expect(text.contains(#"Target="docProps/core.xml""#) && text.contains(#"PartName="/docProps/core.xml""#))
    // The workbook itself is untouched.
    #expect(text.contains("Bob Jones"))
  }

  @Test func copyBetweenSameTypeIncludesAppProperties() async throws {
    let dir = try TempDir()
    let src = try await docx(dir.file("src.docx"), title: "Source title", author: "Dana Source")
    let target = try await docx(dir.file("target.docx"), title: "Target title", author: "Eve Target")
    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let (names, text) = try await contents(out)
    #expect(names.contains("docProps/app.xml"))
    #expect(text.contains("Source title") && !text.contains("Target title"))
    #expect(text.components(separatedBy: "docProps/core.xml").count == 3)  // one relationship, one override
  }

  @Test func officeFilesOnlyTakeOfficeMetadata() async throws {
    let dir = try TempDir()
    let target = try load(try await docx(dir.file("t.docx")))
    let image = try Fixtures.writeImage(to: dir.file("a.jpg"))
    #expect(
      Processor.validate(.copyMetadata(from: image.path), files: target)
        == "Word, Excel and PowerPoint files can only take metadata from another Word, Excel or PowerPoint file."
    )
    let legacy = try load(dir.touch("old.doc", contents: "x"))
    #expect(Processor.validate(.stripAllMetadata, files: legacy)?.contains("isn't supported") == true)
  }
}

import AppKit
import Foundation
import PDFKit
import Testing

@testable import DropCore

/// Conversions that make every dropped type useful beyond PDF: slides, workbooks and pictures
/// to text, workbooks and TSV to JSON, and HTML rendered by WebKit.
@Suite struct FileTypeCoverageTests {
  let dir: URL

  init() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

  static func pptx(_ url: URL) async throws -> URL {
    let a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    func slide(_ paragraphs: [String]) -> String {
      let body = paragraphs.map { "<a:p><a:r><a:t>\($0)</a:t></a:r></a:p>" }.joined()
      return "<p:sld xmlns:p=\"p\" xmlns:a=\"\(a)\"><p:cSld><p:spTree><p:sp><p:txBody>\(body)"
        + "</p:txBody></p:sp></p:spTree></p:cSld></p:sld>"
    }
    return try await SheetFixtures.zip(
      [
        "[Content_Types].xml": "<Types/>",
        "ppt/slides/slide1.xml": slide(["Quarterly review", "Revenue up"]),
        "ppt/slides/slide2.xml": slide(["Next steps"]),
        "ppt/slides/slide10.xml": slide(["Appendix"]),
      ], to: url)
  }

  @Test func pptxSlidesReadInOrder() async throws {
    let deck = try await Self.pptx(file("deck.pptx"))
    let slides = try await OfficeText.pptxSlides(deck)
    #expect(slides == [["Quarterly review", "Revenue up"], ["Next steps"], ["Appendix"]])
  }

  @Test func pptxConvertsToMarkdownAndText() async throws {
    let deck = try DroppedFile.load(await Self.pptx(file("deck.pptx")))
    let md = file("deck.md")
    try await DocumentOps.convert(deck, to: .md, destination: md)
    let markdown = try String(contentsOf: md, encoding: .utf8)
    #expect(markdown.contains("Slide 1"))
    #expect(markdown.contains("Quarterly review"))
    #expect(markdown.contains("Appendix"))
    let txt = file("deck.txt")
    try await DocumentOps.convert(deck, to: .txt, destination: txt)
    #expect(try String(contentsOf: txt, encoding: .utf8).contains("Next steps"))
  }

  @Test func xlsxConvertsToTextOutputsAndJSON() async throws {
    let book = try DroppedFile.load(await SheetFixtures.xlsx(file("scores.xlsx")))
    #expect(DocumentOps.problem(book.kind, output: .html) == nil)
    let html = file("scores.html")
    try await DocumentOps.convert(book, to: .html, destination: html)
    let page = try String(contentsOf: html, encoding: .utf8)
    #expect(page.contains("Ada, L."))
    #expect(page.contains("<table"))

    var urls: [URL] = []
    urls = try await SpreadsheetOps.exportData(book.url, format: .xlsx, to: .json) { _ in
      self.file("scores.json")
    }
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: urls[0])) as? [[String: String]]
    #expect(json?.first?["Name"] == "Ada, L.")
    #expect(json?.first?["TRUE"] == "9.5")
  }

  @Test func tsvConvertsToJSON() throws {
    let tsv = file("people.tsv")
    try "name\tcity\nAda\tLondon\n".write(to: tsv, atomically: true, encoding: .utf8)
    #expect(try DroppedFile.load(tsv).kind.dataFormat == .csv)
    let out = file("people.json")
    try DataOps.convert(tsv, to: .json, destination: out)
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: out)) as? [[String: String]]
    #expect(json == [["name": "Ada", "city": "London"]])
  }

  @Test func imageTextIsReadWithOCR() async throws {
    let png = file("sign.png")
    let image = NSImage(size: CGSize(width: 900, height: 200), flipped: false) { rect in
      NSColor.white.setFill()
      rect.fill()
      ("HELLO DROP" as NSString).draw(
        at: CGPoint(x: 40, y: 60), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 72)])
      return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: png)
    let picture = try DroppedFile.load(png)
    #expect(DocumentOps.problem(picture.kind, output: .txt) == nil)
    #expect(DocumentOps.problem(picture.kind, output: .pdf) != nil)
    let out = file("sign.txt")
    try await DocumentOps.convert(picture, to: .txt, destination: out)
    #expect(try String(contentsOf: out, encoding: .utf8).uppercased().contains("HELLO"))
  }

  @Test func slidesAndWorkbooksOfferTextOutputs() {
    #expect(DocumentOps.problem(.office(.pptx), output: .md) == nil)
    #expect(DocumentOps.problem(.office(.key), output: .txt) == nil)
    #expect(DocumentOps.problem(.office(.xlsx), output: .html) == nil)
    #expect(DocumentOps.problem(.office(.pptx), output: .epubFixed) != nil)
  }

  @Test func htmlRendersToPaginatedPDF() async throws {
    let html = file("page.html")
    let rows = (1...120).map { "<tr><td>Row \($0)</td><td>Value</td></tr>" }.joined()
    try "<html><body><h1>Report</h1><table border=1>\(rows)</table></body></html>"
      .write(to: html, atomically: true, encoding: .utf8)
    let out = file("page.pdf")
    try await DocumentOps.convert(try DroppedFile.load(html), to: .pdf, destination: out)
    let pdf = try #require(PDFDocument(url: out))
    #expect(pdf.pageCount > 1)
    #expect(pdf.string?.contains("Row 120") == true)
  }

  @Test func htmlPDFRunsNoScriptsAndFetchesNothing() async throws {
    let html = file("tracker.html")
    let page = """
      <html><body><h1>Offline</h1>
      <script>document.write('SCRIPT RAN')</script>
      <img src="https://example.com/pixel.png"><img srcset="https://example.com/a.png 2x">
      <p>Body text</p></body></html>
      """
    try page.write(to: html, atomically: true, encoding: .utf8)
    let out = file("tracker.pdf")
    try await DocumentOps.convert(try DroppedFile.load(html), to: .pdf, destination: out)
    let text = try #require(PDFDocument(url: out)?.string)
    #expect(text.contains("Body text"))
    #expect(!text.contains("SCRIPT RAN"))
  }
}

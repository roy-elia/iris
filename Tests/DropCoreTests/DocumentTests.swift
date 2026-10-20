import AppKit
import Foundation
import PDFKit
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// Builds document fixtures with AppKit.
enum DocFixtures {
  static func rich() -> NSAttributedString {
    let s = NSMutableAttributedString()
    s.append(
      NSAttributedString(string: "Report Title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 26)]))
    s.append(NSAttributedString(string: "Plain and ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
    s.append(NSAttributedString(string: "bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
    s.append(NSAttributedString(string: " words with a ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
    s.append(
      NSAttributedString(
        string: "link",
        attributes: [.font: NSFont.systemFont(ofSize: 12), .link: URL(string: "https://example.com")!]))
    s.append(NSAttributedString(string: ".\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
    s.append(
      NSAttributedString(string: "Section Two\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]))
    s.append(
      NSAttributedString(string: "More body text here.\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
    )
    return s
  }

  static func rtf(_ url: URL) throws -> URL {
    let s = rich()
    try s.data(
      from: NSRange(location: 0, length: s.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    .write(to: url)
    return url
  }

  static func docx(_ url: URL) throws -> URL {
    let s = rich()
    try s.data(
      from: NSRange(location: 0, length: s.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
    ).write(to: url)
    return url
  }

  static func text(_ url: URL, _ content: String) throws -> URL {
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  /// A PDF with `pages` pages of selectable text ("Page N").
  static func pdf(_ url: URL, pages: Int = 3) throws -> URL {
    var box = CGRect(x: 0, y: 0, width: 300, height: 400)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    for n in 1...pages {
      ctx.beginPDFPage(nil)
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "Page \(n) text", attributes: [.font: NSFont.systemFont(ofSize: 24)]))
      ctx.textPosition = CGPoint(x: 40, y: 300)
      CTLineDraw(line, ctx)
      ctx.endPDFPage()
    }
    ctx.closePDF()
    return url
  }

  /// A PDF whose only page is an image of text (needs OCR).
  static func scannedPDF(_ url: URL, dir: TempDir) throws -> URL {
    let w = 1200
    let h = 400
    let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: "Invoice number 4821",
        attributes: [.font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.black]
      ))
    ctx.textPosition = CGPoint(x: 60, y: 160)
    CTLineDraw(line, ctx)
    let png = dir.file("scan.png")
    try ImageOps.write(ctx.makeImage()!, as: .png, quality: 1, to: png)
    try PDFOps.imagesToPDF([png], destination: url)
    return url
  }
}

@Suite struct DocumentModelTests {
  @Test func recognisesDocumentKinds() {
    #expect(FileKind(url: URL(fileURLWithPath: "/a.docx")) == .document(.docx))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.markdown")) == .document(.md))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.textClipping")) == .document(.textClipping))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.KEY")) == .office(.key))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.csv")) == .office(.csv))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.vtt")) == .subtitle(.vtt))
    #expect(FileKind(url: URL(fileURLWithPath: "/a.zip")) == .archive)
  }

  @Test func acceptsPackagesButNotPlainFolders() throws {
    let dir = try TempDir()
    let rtfd = dir.file("Notes.rtfd")
    let s = DocFixtures.rich()
    let wrapper = try s.fileWrapper(
      from: NSRange(location: 0, length: s.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    try wrapper.write(to: rtfd, options: .atomic, originalContentsURL: nil)
    let file = try DroppedFile.load(rtfd)
    #expect(file.kind == .document(.rtfd) && file.byteSize > 0)
    let folder = dir.file("Folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(throws: DropError.self) { try DroppedFile.load(folder) }
  }

  @Test func markdownCoversCommonSyntax() {
    let html = Markdown.html(
      """
      # Title
      Some *em* and **strong** and `code` with [a link](https://x.org "t").

      - one
      - two
        - nested
      1. first
      2. second

      > quoted

      ```swift
      let x = 1 < 2
      ```

      | A | B |
      |---|---|
      | 1 | 2 |

      ---
      snake_case_name stays <b>escaped</b>
      """)
    #expect(html.contains("<h1>Title</h1>"))
    #expect(
      html.contains("<em>em</em>") && html.contains("<strong>strong</strong>")
        && html.contains("<code>code</code>"))
    #expect(html.contains("<a href=\"https://x.org\">a link</a>"))
    #expect(html.contains("<ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul>"))
    #expect(html.contains("<ol><li>first</li><li>second</li></ol>"))
    #expect(html.contains("<blockquote><p>quoted</p></blockquote>"))
    #expect(html.contains("<pre><code class=\"language-swift\">let x = 1 &lt; 2</code></pre>"))
    #expect(html.contains("<th>A</th>") && html.contains("<td>2</td>"))
    #expect(html.contains("<hr>"))
    #expect(html.contains("snake_case_name") && html.contains("&lt;b&gt;escaped&lt;/b&gt;"))
  }

  @Test func blocksFindHeadingsAndInlineStyles() {
    let blocks = RichText.blocks(from: DocFixtures.rich())
    #expect(blocks.count == 4)
    guard case .heading(1, let title) = blocks[0], case .paragraph(let body) = blocks[1],
      case .heading(2, _) = blocks[2]
    else {
      Issue.record("unexpected blocks \(blocks)")
      return
    }
    #expect(title.map(\.text).joined() == "Report Title")
    #expect(body.contains { $0.bold && $0.text == "bold" })
    #expect(body.contains { $0.link == "https://example.com" })
    let md = RichText.markdown(blocks)
    #expect(md.contains("# Report Title\n\nPlain and **bold** words with a [link](https://example.com)."))
    #expect(md.contains("## Section Two"))
  }

  @Test func csvParserHandlesQuotes() {
    let rows = TableOps.parse("name,note\n\"Smith, J\",\"said \"\"hi\"\"\"\nx,\n", separator: ",")
    #expect(rows == [["name", "note"], ["Smith, J", "said \"hi\""], ["x", ""]])
  }

  @Test func subtitlesRoundTrip() {
    let srt = """
      1
      00:00:01,000 --> 00:00:02,500
      Hello there

      2
      00:01:02,040 --> 00:01:04,000
      <v Sam>Two lines
      here
      """
    let cues = SubtitleOps.parse(srt)
    #expect(cues.count == 2)
    #expect(cues[1].start == 62.04 && cues[1].text == "<v Sam>Two lines\nhere")
    let vtt = SubtitleOps.write(cues, as: .vtt)
    #expect(vtt.hasPrefix("WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nHello there"))
    let back = SubtitleOps.parse(vtt)
    #expect(back == cues)
    #expect(SubtitleOps.write(back, as: .srt).contains("2\n00:01:02,040 --> 00:01:04,000\nTwo lines\nhere"))
    #expect(SubtitleOps.time("02:03.5") == 123.5)
    #expect(SubtitleOps.parse("WEBVTT\n\nnot a cue").isEmpty)
  }

  @Test func archiveEntryChecks() {
    #expect(ArchiveOps.isSafe("folder/file.txt"))
    #expect(!ArchiveOps.isSafe("../evil.txt"))
    #expect(!ArchiveOps.isSafe("a/../../b"))
    #expect(!ArchiveOps.isSafe("/etc/passwd"))
    #expect(
      ArchiveOps.uncompressedBytes("3 files, 12345 bytes uncompressed, 999 bytes compressed:  91.9%") == 12345
    )
  }

  @Test func remoteResourcesAreStripped() {
    let html =
      #"<img src="https://t.example/p.gif" alt="x"><script>alert(1)</script><link rel="stylesheet" href="http://x/s.css"><img src="local.png">"#
    let safe = RichText.stripRemote(html)
    #expect(!safe.contains("t.example") && !safe.contains("script") && !safe.contains("s.css"))
    #expect(safe.contains("local.png"))
  }

  @Test func validationMessages() throws {
    let dir = try TempDir()
    let pdf = try DocFixtures.pdf(dir.file("a.pdf"))
    let srt = try DocFixtures.text(dir.file("a.srt"), "1\n00:00:01,000 --> 00:00:02,000\nHi\n")
    #expect(Processor.validate(.convertDocument(.pdf), files: try load(pdf)) == "It's already a PDF.")
    #expect(Processor.validate(.convertDocument(.txt), files: try load(srt))?.contains("documents") == true)
    #expect(
      Processor.validate(.organizePDF(PDFPagePlan(pages: [])), files: try load(pdf))
        == "Keep at least one page.")
    #expect(
      Processor.validate(.compress(quality: 0.5), files: try load(srt))
        == "Compress works on images and PDFs.")
    if !IWorkApp.pages.isInstalled {
      #expect(Processor.validate(.convertDocument(.pages), files: try load(pdf)) == "Pages: Needs Pages.")
    }
  }
}

@Suite(.serialized) struct DocumentOpsTests {
  @Test(arguments: [DocumentOutput.pdf, .docx, .txt, .md, .html, .epub])
  func convertsRichTextToEachOutput(output: DocumentOutput) async throws {
    let dir = try TempDir()
    let rtf = try DocFixtures.rtf(dir.file("report.rtf"))
    let result = await Processor(settings: AppSettings()).run(.convertDocument(output), on: try load(rtf))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "report.\(output.fileExtension)")
    switch output {
    case .pdf:
      let doc = try #require(PDFDocument(url: out))
      #expect(doc.string?.contains("Section Two") == true)
    case .txt, .md, .html:
      let text = try String(contentsOf: out, encoding: .utf8)
      #expect(text.contains("Section Two"))
      if output == .md { #expect(text.contains("**bold**")) }
      if output == .html { #expect(text.contains("<h1>Report Title</h1>")) }
    case .docx:
      let back = try NSAttributedString(url: out, options: [:], documentAttributes: nil)
      #expect(back.string.contains("Report Title"))
    case .epub:
      let names = try await SystemProcess.run("/usr/bin/zipinfo", ["-1", out.path])
      let list = String(decoding: names.stdout, as: UTF8.self).split(separator: "\n")
      #expect(list.first == "mimetype")
      #expect(list.contains("OEBPS/content.opf") && list.contains("OEBPS/nav.xhtml"))
      // Two top-level headings would be two chapters; this one has one H1.
      #expect(list.contains("OEBPS/chapter1.xhtml"))
    default: break
    }
  }

  @Test func readsMarkdownHTMLDocxCSVAndClippings() async throws {
    let dir = try TempDir()
    let md = try DocFixtures.text(dir.file("notes.md"), "# Notes\n\nA **bold** idea.\n\n- one\n- two\n")
    let html = try DocFixtures.text(dir.file("page.html"), "<h1>Page</h1><p>Hello <i>web</i></p>")
    let docx = try DocFixtures.docx(dir.file("letter.docx"))
    let csv = try DocFixtures.text(dir.file("table.csv"), "Name,Score\nAda,9\n\"Lin, M\",8\n")
    let clip = dir.file("snippet.textClipping")
    let plist: [String: Any] = ["UTI-Data": ["public.utf8-plain-text": "Clipped words"]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: clip)

    let result = await Processor(settings: AppSettings()).run(
      .convertDocument(.md), on: try load(md, html, docx, csv, clip))
    #expect(result.failures.isEmpty, "\(result.failures)")
    let texts = try result.outputs.map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(texts.count == 5)
    #expect(texts[0].contains("# Notes") && texts[0].contains("**bold**") && texts[0].contains("- one"))
    #expect(texts[1].contains("# Page") && texts[1].contains("*web*"))
    #expect(texts[2].contains("Report Title"))
    #expect(texts[3].contains("| Name | Score |") && texts[3].contains("| Lin, M | 8 |"))
    #expect(texts[4].contains("Clipped words"))
  }

  @Test func markdownToHTMLIsDirect() async throws {
    let dir = try TempDir()
    let md = try DocFixtures.text(dir.file("notes.md"), "## Hi\n\n1. a\n2. b\n")
    let result = await Processor(settings: AppSettings()).run(.convertDocument(.html), on: try load(md))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let html = try String(contentsOf: out, encoding: .utf8)
    #expect(html.contains("<h2>Hi</h2>") && html.contains("<ol><li>a</li><li>b</li></ol>"))
  }

  @Test func pdfToTextAndImages() async throws {
    let dir = try TempDir()
    let pdf = try DocFixtures.pdf(dir.file("deck.pdf"))
    let text = await Processor(settings: AppSettings()).run(.convertDocument(.txt), on: try load(pdf))
    let out = try #require(text.outputs.first, "\(text.failures)")
    let s = try String(contentsOf: out, encoding: .utf8)
    #expect(s.contains("Page 1 text") && s.contains("Page 3 text"))

    let images = await Processor(settings: AppSettings()).run(.pdfToImages(.png), on: try load(pdf))
    #expect(
      images.outputs.map(\.lastPathComponent) == ["deck page 1.png", "deck page 2.png", "deck page 3.png"],
      "\(images.failures)")
    let image = try ImageOps.loadOriented(images.outputs[0])
    #expect(image.width == 600 && image.height == 800)
  }

  @Test func scannedPagesAreReadWithOCR() async throws {
    let dir = try TempDir()
    let pdf = try DocFixtures.scannedPDF(dir.file("scan.pdf"), dir: dir)
    let result = await Processor(settings: AppSettings()).run(.convertDocument(.txt), on: try load(pdf))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(try String(contentsOf: out, encoding: .utf8).contains("4821"))
  }

  @Test func organizesPages() async throws {
    let dir = try TempDir()
    let pdf = try DocFixtures.pdf(dir.file("a.pdf"))
    let plan = PDFPagePlan(pages: [PDFPageRef(index: 2, rotation: 90), PDFPageRef(index: 0)])
    let result = await Processor(settings: AppSettings()).run(.organizePDF(plan), on: try load(pdf))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "a organized.pdf")
    let doc = try #require(PDFDocument(url: out))
    #expect(doc.pageCount == 2)
    #expect(doc.page(at: 0)?.string?.contains("Page 3") == true)
    #expect(doc.page(at: 0)?.rotation == 90 && doc.page(at: 1)?.rotation == 0)
  }

  @Test func equalWidthsScalesPages() throws {
    let dir = try TempDir()
    let a = try DocFixtures.pdf(dir.file("a.pdf"), pages: 1)
    let rotated = dir.file("b.pdf")
    try PDFPageOps.organize(
      a,
      plan: PDFPagePlan(
        pages: [PDFPageRef(index: 0), PDFPageRef(index: 0, rotation: 90)], equalWidths: true),
      destination: rotated)
    let doc = try #require(PDFDocument(url: rotated))
    let widths = (0..<doc.pageCount).map { doc.page(at: $0)!.bounds(for: .mediaBox).width }
    #expect(widths == [400, 400])
  }

  @Test func fixedLayoutEPUBFromPDF() async throws {
    let dir = try TempDir()
    let pdf = try DocFixtures.pdf(dir.file("comic.pdf"), pages: 2)
    let result = await Processor(settings: AppSettings()).run(.convertDocument(.epubFixed), on: try load(pdf))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let names = String(
      decoding: try await SystemProcess.run("/usr/bin/zipinfo", ["-1", out.path]).stdout, as: UTF8.self)
    #expect(names.contains("OEBPS/page2.jpg") && names.contains("OEBPS/page2.xhtml"))
  }

  @Test func epubRoundTrip() async throws {
    let dir = try TempDir()
    let md = try DocFixtures.text(
      dir.file("book.md"), "# Chapter One\n\nIt began.\n\n# Chapter Two\n\nIt ended with **style**.\n")
    let made = await Processor(settings: AppSettings()).run(.convertDocument(.epub), on: try load(md))
    let epub = try #require(made.outputs.first, "\(made.failures)")
    let names = String(
      decoding: try await SystemProcess.run("/usr/bin/zipinfo", ["-1", epub.path]).stdout, as: UTF8.self)
    #expect(names.contains("OEBPS/chapter2.xhtml"))

    let back = await Processor(settings: AppSettings()).run(.convertDocument(.txt), on: try load(epub))
    let txt = try #require(back.outputs.first, "\(back.failures)")
    let text = try String(contentsOf: txt, encoding: .utf8)
    #expect(text.contains("Chapter One") && text.contains("It ended with style."))
  }

  @Test func readsPagesPreviewPDF() async throws {
    let dir = try TempDir()
    let package = dir.file("Essay.pages")
    try FileManager.default.createDirectory(
      at: package.appendingPathComponent("QuickLook"), withIntermediateDirectories: true)
    _ = try DocFixtures.pdf(package.appendingPathComponent("QuickLook/Preview.pdf"), pages: 1)
    let result = await Processor(settings: AppSettings()).run(.convertDocument(.txt), on: try load(package))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(try String(contentsOf: out, encoding: .utf8).contains("Page 1 text"))
    if !IWorkApp.pages.isInstalled {
      let pdf = await Processor(settings: AppSettings()).run(.convertDocument(.pdf), on: try load(package))
      #expect(PDFDocument(url: try #require(pdf.outputs.first, "\(pdf.failures)"))?.pageCount == 1)
    }
  }

  @Test func tellsDocumentsFromPreviewOnlyPackages() async throws {
    let dir = try TempDir()
    let previewOnly = dir.file("Preview.key")
    try FileManager.default.createDirectory(
      at: previewOnly.appendingPathComponent("QuickLook"), withIntermediateDirectories: true)
    #expect(!IWorkOps.hasDocumentData(previewOnly))
    let package = dir.file("Real.key")
    try FileManager.default.createDirectory(
      at: package.appendingPathComponent("Index"), withIntermediateDirectories: true)
    #expect(IWorkOps.hasDocumentData(package))
    // A single-file document is a zip holding Index/…
    let src = dir.file("src")
    try FileManager.default.createDirectory(
      at: src.appendingPathComponent("Index"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: src.appendingPathComponent("Index/Document.iwa"))
    let zipped = dir.file("Flat.numbers")
    try await SystemProcess.run("/usr/bin/zip", ["-qr", zipped.path, "Index"], in: src)
    #expect(IWorkOps.hasDocumentData(zipped))
    #expect(IWorkOps.hasDocumentData(dir.file("Deck.pptx")))
  }

  /// The package holds only a saved preview, so this also covers Keynote refusing it
  /// (when installed) and the fallback to that preview.
  @Test func savesPresentationSlidesAsImages() async throws {
    let dir = try TempDir()
    let deck = dir.file("Deck.key")
    try FileManager.default.createDirectory(
      at: deck.appendingPathComponent("QuickLook"), withIntermediateDirectories: true)
    _ = try DocFixtures.pdf(deck.appendingPathComponent("QuickLook/Preview.pdf"), pages: 3)
    let files = try load(deck)
    #expect(Processor.validate(.pdfToImages(.png), files: files) == nil)
    let result = await Processor(settings: AppSettings()).run(.pdfToImages(.png), on: files)
    #expect(result.failures.isEmpty, "\(result.failures)")
    #expect(
      result.outputs.map(\.lastPathComponent) == ["Deck slide 1.png", "Deck slide 2.png", "Deck slide 3.png"])
    #expect(result.outputs.allSatisfy { (try? ImageOps.loadOriented($0)) != nil })
    let sheet = try DocFixtures.text(dir.file("t.csv"), "a,b\n")
    #expect(Processor.validate(.pdfToImages(.png), files: try load(sheet))?.contains("presentations") == true)
  }

  @Test func csvToPDF() async throws {
    let dir = try TempDir()
    let csv = try DocFixtures.text(dir.file("scores.csv"), "Name,Score\nAda,9\nLin,8\n")
    let result = await Processor(settings: AppSettings()).run(.convertDocument(.pdf), on: try load(csv))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(PDFDocument(url: out)?.string?.contains("Ada") == true)
  }

  @Test func convertsSubtitleFiles() async throws {
    let dir = try TempDir()
    let srt = try DocFixtures.text(dir.file("film.srt"), "1\n00:00:01,000 --> 00:00:02,000\nHi\n")
    let result = await Processor(settings: AppSettings()).run(.convertSubtitles(.vtt), on: try load(srt))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(try String(contentsOf: out, encoding: .utf8) == "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n")
    let bad = try DocFixtures.text(dir.file("bad.srt"), "nothing here")
    let failed = await Processor(settings: AppSettings()).run(.convertSubtitles(.vtt), on: try load(bad))
    #expect(failed.failures.first?.message == "No valid subtitle cues were found in bad.srt.")
  }

  @Test func extractsArchives() async throws {
    let dir = try TempDir()
    let src = dir.file("src")
    try FileManager.default.createDirectory(
      at: src.appendingPathComponent("inner"), withIntermediateDirectories: true)
    try "hello".write(to: src.appendingPathComponent("inner/a.txt"), atomically: true, encoding: .utf8)
    let zip = dir.file("bundle.zip")
    try await SystemProcess.run("/usr/bin/zip", ["-rq", zip.path, "inner"], in: src)
    let result = await Processor(settings: AppSettings()).run(.extractArchive, on: try load(zip))
    let folder = try #require(result.outputs.first, "\(result.failures)")
    #expect(folder.lastPathComponent == "bundle")
    #expect(try String(contentsOf: folder.appendingPathComponent("inner/a.txt"), encoding: .utf8) == "hello")
  }
}

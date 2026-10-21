import AppKit
import Foundation
import PDFKit

/// Rich text in and out: reading documents into `NSAttributedString`, a simple block model
/// for Markdown and XHTML output, and paginated PDF rendering with TextKit.
public enum RichText {
  static var bodyFont: NSFont { .systemFont(ofSize: 12) }
  /// US Letter, in points.
  static let pageSize = CGSize(width: 612, height: 792)
  static let pageMargin: CGFloat = 54

  // MARK: Reading

  /// Reads plain text, guessing the encoding.
  static func readPlainText(_ url: URL) throws -> String {
    var encoding = String.Encoding.utf8
    if let s = try? String(contentsOf: url, usedEncoding: &encoding) { return s }
    let data = try Data(contentsOf: url)
    if let s = String(data: data, encoding: .utf8) { return s }
    if let s = String(data: data, encoding: .windowsCP1252) { return s }
    throw DropError.readFailed(url.lastPathComponent)
  }

  static func plain(_ s: String) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: bodyFont, .foregroundColor: NSColor.black])
  }

  /// Reads HTML with AppKit's importer (which must run on the main thread). Remote images,
  /// stylesheets and scripts are removed first so nothing is fetched from the network.
  static func readHTML(_ html: String, baseURL: URL?) async throws -> NSAttributedString {
    let safe = stripRemote(html)
    let data = Data(safe.utf8)
    let box = try await MainActor.run {
      var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue,
      ]
      if let baseURL { options[.baseURL] = baseURL }
      return UncheckedBox(try NSAttributedString(data: data, options: options, documentAttributes: nil))
    }
    return box.value
  }

  static func stripRemote(_ html: String) -> String {
    var s = html
    let patterns = [
      #"<script\b[^>]*>[\s\S]*?</script>"#,
      #"<link\b[^>]*>"#,
      #"<iframe\b[^>]*>[\s\S]*?</iframe>"#,
      #"(<img\b[^>]*?)\ssrc\s*=\s*["']?(?:https?:)?//[^"'\s>]*["']?"#,
      #"url\(\s*["']?(?:https?:)?//[^)]*\)"#,
    ]
    for (n, p) in patterns.enumerated() {
      guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
      let template = n == 3 ? "$1" : (n == 4 ? "none" : "")
      s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
    return s
  }

  /// Reads a document, PDF, table or clipping into attributed text.
  public static func load(_ url: URL, kind: FileKind) async throws -> NSAttributedString {
    let name = url.lastPathComponent
    switch kind {
    case .document(let format):
      switch format {
      case .txt: return plain(try readPlainText(url))
      case .md:
        let html = Markdown.page(try readPlainText(url), title: url.deletingPathExtension().lastPathComponent)
        return try await readHTML(html, baseURL: url.deletingLastPathComponent())
      case .html: return try await readHTML(try readPlainText(url), baseURL: url.deletingLastPathComponent())
      case .epub: return try await EPUBOps.read(url)
      case .pages:
        let pdf = try IWorkOps.previewPDF(of: url)
        return try PDFText.attributed(pdf, name: name)
      case .textClipping: return try ClippingOps.read(url)
      case .docx, .doc, .odt, .rtf, .rtfd:
        do {
          return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
          throw DropError.readFailed(name)
        }
      }
    case .pdf:
      guard let doc = PDFDocument(url: url) else { throw DropError.readFailed(name) }
      if doc.isLocked { throw DropError.wrongInput("\(name) is password-protected.") }
      return try PDFText.attributed(doc, name: name)
    case .office(let format) where format.isTable:
      let rows = TableOps.parse(try readPlainText(url), separator: format == .tsv ? "\t" : ",")
      return try await readHTML(TableOps.html(rows, title: name), baseURL: nil)
    case .office(let format) where format.isPresentation:
      return try await OfficeText.presentation(url, format: format)
    case .office(let format):
      return try await OfficeText.spreadsheet(url, format: format)
    case .image:
      return try OfficeText.image(url)
    default:
      throw DropError.unsupportedFile(name)
    }
  }

  // MARK: Writing

  /// Writes attributed text as `output`. EPUB, Pages and fixed-layout EPUB are handled by
  /// their own ops.
  public static func write(_ text: NSAttributedString, as output: DocumentOutput, title: String, to url: URL)
    async throws
  {
    let whole = NSRange(location: 0, length: text.length)
    guard text.string.contains(where: { !$0.isWhitespace }) else {
      throw DropError.wrongInput("There's no text to convert.")
    }
    switch output {
    case .txt:
      try text.string.write(to: url, atomically: true, encoding: .utf8)
    case .md:
      try markdown(blocks(from: text)).write(to: url, atomically: true, encoding: .utf8)
    case .rtf:
      try text.data(from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        .write(to: url)
    case .docx:
      try text.data(
        from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
      )
      .write(to: url)
    case .html:
      let body = xhtml(blocks(from: text))
      let page = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(Markdown.escape(title))</title>
        <style>body{font:16px/1.5 -apple-system,sans-serif;max-width:42em;margin:2em auto;padding:0 1em}
        table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:4px 8px}</style></head>
        <body>
        \(body)
        </body></html>
        """
      try page.write(to: url, atomically: true, encoding: .utf8)
    case .pdf:
      try renderPDF(text, to: url)
    case .epub:
      try EPUBOps.write(blocks(from: text), title: title, to: url)
    case .pages:
      try await IWorkOps.writePages(text, to: url)
    case .epubFixed:
      throw DropError.wrongInput("Page-image EPUBs are made from PDFs.")
    }
  }

  /// Lays the text out on Letter pages with TextKit and draws each page into a PDF.
  public static func renderPDF(_ text: NSAttributedString, to url: URL) throws {
    let storage = NSTextStorage(attributedString: text)
    let layout = NSLayoutManager()
    storage.addLayoutManager(layout)
    let textSize = CGSize(width: pageSize.width - 2 * pageMargin, height: pageSize.height - 2 * pageMargin)
    var containers: [NSTextContainer] = []
    while containers.count < 10_000 {
      let container = NSTextContainer(size: textSize)
      container.lineFragmentPadding = 0
      layout.addTextContainer(container)
      containers.append(container)
      let range = layout.glyphRange(for: container)
      if NSMaxRange(range) >= layout.numberOfGlyphs { break }
    }
    var box = CGRect(origin: .zero, size: pageSize)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
      throw DropError.writeFailed(url.lastPathComponent)
    }
    let previous = NSGraphicsContext.current
    defer { NSGraphicsContext.current = previous }
    for container in containers {
      context.beginPDFPage(nil)
      context.saveGState()
      context.translateBy(x: 0, y: pageSize.height)
      context.scaleBy(x: 1, y: -1)
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      let range = layout.glyphRange(for: container)
      let origin = CGPoint(x: pageMargin, y: pageMargin)
      layout.drawBackground(forGlyphRange: range, at: origin)
      layout.drawGlyphs(forGlyphRange: range, at: origin)
      context.restoreGState()
      context.endPDFPage()
    }
    context.closePDF()
  }

  // MARK: Blocks

  public struct Run: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var code = false
    public var strike = false
    public var link: String?
  }

  public enum Block: Equatable, Sendable {
    case heading(Int, [Run])
    case paragraph([Run])
    case listItem(ordered: Bool, level: Int, [Run])
    case code(String)
    case table([[String]])
  }

  /// Splits attributed text into headings, paragraphs, list items, code and tables, judging
  /// headings by font size relative to the body text.
  public static func blocks(from text: NSAttributedString) -> [Block] {
    let ns = text.string as NSString
    let base = bodySize(text)
    var result: [Block] = []
    var tableRows: [[String]] = []
    var currentTable: NSTextTable?
    var tableRow = -1

    func flushTable() {
      if !tableRows.isEmpty { result.append(.table(tableRows)) }
      tableRows = []
      currentTable = nil
      tableRow = -1
    }

    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) {
      _, range, _, _ in
      guard range.length > 0 else { return }
      let style =
        text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
      let raw = ns.substring(with: range)

      if let cell = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
        if cell.table !== currentTable {
          flushTable()
          currentTable = cell.table
        }
        if cell.startingRow != tableRow {
          tableRows.append([])
          tableRow = cell.startingRow
        }
        tableRows[tableRows.count - 1].append(raw.trimmingCharacters(in: .whitespaces))
        return
      }
      flushTable()
      if raw.trimmingCharacters(in: .whitespaces).isEmpty { return }

      var runs = Self.runs(text, range: range)
      let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
      let isMono = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
      if let lists = style?.textLists, !lists.isEmpty {
        stripListMarker(&runs)
        let ordered =
          lists.last.map {
            !["{disc}", "{circle}", "{square}", "{hyphen}", "{box}", "{check}", "{diamond}"].contains(
              $0.markerFormat.rawValue)
          } ?? false
        result.append(.listItem(ordered: ordered, level: lists.count, runs))
      } else if isMono, runs.allSatisfy(\.code) || runs.count == 1 {
        let code = raw
        if case .code(let previous) = result.last {
          result[result.count - 1] = .code(previous + "\n" + code)
        } else {
          result.append(.code(code))
        }
      } else if let level = headingLevel(text, range: range, base: base), raw.count < 200 {
        for i in runs.indices { runs[i].bold = false }
        result.append(.heading(level, runs))
      } else {
        result.append(.paragraph(runs))
      }
    }
    flushTable()
    return result
  }

  /// The most common font size, weighted by characters.
  static func bodySize(_ text: NSAttributedString) -> CGFloat {
    var counts: [CGFloat: Int] = [:]
    text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      let size = (value as? NSFont)?.pointSize ?? 12
      counts[size.rounded(), default: 0] += range.length
    }
    return counts.max { $0.value < $1.value }?.key ?? 12
  }

  static func headingLevel(_ text: NSAttributedString, range: NSRange, base: CGFloat) -> Int? {
    var size: CGFloat = 0
    text.enumerateAttribute(.font, in: range) { value, _, _ in
      size = max(size, (value as? NSFont)?.pointSize ?? 0)
    }
    let ratio = size / max(base, 1)
    switch ratio {
    case 1.9...: return 1
    case 1.45..<1.9: return 2
    case 1.15..<1.45: return 3
    default: return nil
    }
  }

  static func runs(_ text: NSAttributedString, range: NSRange) -> [Run] {
    var runs: [Run] = []
    text.enumerateAttributes(in: range) { attrs, r, _ in
      var piece = (text.string as NSString).substring(with: r)
      piece = piece.replacingOccurrences(of: "\u{2028}", with: "\n")
      guard !piece.isEmpty else { return }
      let font = attrs[.font] as? NSFont
      let traits = font?.fontDescriptor.symbolicTraits ?? []
      var run = Run(text: piece)
      run.bold = traits.contains(.bold)
      run.italic = traits.contains(.italic)
      run.code = traits.contains(.monoSpace)
      run.strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
      if let link = attrs[.link] as? URL {
        run.link = link.absoluteString
      } else if let link = attrs[.link] as? String {
        run.link = link
      }
      if let last = runs.last, last.bold == run.bold, last.italic == run.italic, last.code == run.code,
        last.strike == run.strike, last.link == run.link
      {
        runs[runs.count - 1].text += piece
      } else {
        runs.append(run)
      }
    }
    // Trim the paragraph's outer whitespace.
    if !runs.isEmpty {
      while let f = runs.first?.text.first, f == " " || f == "\t" { runs[0].text.removeFirst() }
      while let l = runs.last?.text.last, l.isWhitespace { runs[runs.count - 1].text.removeLast() }
      runs.removeAll { $0.text.isEmpty }
    }
    return runs
  }

  /// Removes the "•" or "1." marker AppKit puts at the start of list items.
  static func stripListMarker(_ runs: inout [Run]) {
    guard !runs.isEmpty else { return }
    var t = runs[0].text
    if let re = try? NSRegularExpression(pattern: #"^\s*([•◦▪‣⁃\-–*]|\(?[0-9a-zA-Z]{1,4}[.)])\s+"#) {
      t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
    }
    runs[0].text = t
    runs.removeAll { $0.text.isEmpty }
  }

  // MARK: Markdown out

  public static func markdown(_ blocks: [Block]) -> String {
    var out: [String] = []
    var previousWasList = false
    for block in blocks {
      let isList: Bool
      switch block {
      case .heading(let level, let runs):
        isList = false
        out.append(String(repeating: "#", count: level) + " " + mdInline(runs))
      case .paragraph(let runs):
        isList = false
        out.append(mdInline(runs))
      case .listItem(let ordered, let level, let runs):
        isList = true
        let indent = String(repeating: "  ", count: max(level - 1, 0) * (ordered ? 2 : 1))
        let item = indent + (ordered ? "1. " : "- ") + mdInline(runs)
        if previousWasList, let last = out.popLast() {
          out.append(last + "\n" + item)
        } else {
          out.append(item)
        }
      case .code(let code):
        isList = false
        out.append("```\n\(code)\n```")
      case .table(let rows):
        isList = false
        guard let header = rows.first else { continue }
        let width = rows.map(\.count).max() ?? header.count
        func row(_ cells: [String]) -> String {
          let padded = cells + Array(repeating: "", count: max(width - cells.count, 0))
          return "| " + padded.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ")
            + " |"
        }
        let divider = "|" + Array(repeating: " --- |", count: width).joined()
        out.append(([row(header), divider] + rows.dropFirst().map(row)).joined(separator: "\n"))
      }
      previousWasList = isList
    }
    return out.joined(separator: "\n\n") + "\n"
  }

  static func mdEscape(_ s: String) -> String {
    var out = ""
    for c in s {
      if "\\`*_[]<>".contains(c) { out.append("\\") }
      out.append(c)
    }
    return out
  }

  static func mdInline(_ runs: [Run]) -> String {
    runs.map { run in
      if run.code { return "`\(run.text.replacingOccurrences(of: "`", with: "'"))`" }
      // Keep spaces outside the markers, where Markdown expects them.
      let core = run.text.trimmingCharacters(in: .whitespaces)
      guard !core.isEmpty else { return run.text }
      let lead = String(run.text.prefix { $0 == " " })
      let trail = String(run.text.reversed().prefix { $0 == " " })
      var s = mdEscape(core).replacingOccurrences(of: "\n", with: "  \n")
      if run.strike { s = "~~\(s)~~" }
      if run.italic { s = "*\(s)*" }
      if run.bold { s = "**\(s)**" }
      if let link = run.link { s = "[\(s)](\(link.replacingOccurrences(of: " ", with: "%20")))" }
      return lead + s + trail
    }.joined()
  }

  // MARK: XHTML out

  public static func xhtml(_ blocks: [Block]) -> String {
    var out: [String] = []
    // Open lists as (ordered) per level.
    var stack: [Bool] = []
    func closeLists(to level: Int) {
      while stack.count > level { out.append(stack.removeLast() ? "</li></ol>" : "</li></ul>") }
    }
    for block in blocks {
      if case .listItem(let ordered, let level, let runs) = block {
        if stack.count == level, stack.last != ordered {
          closeLists(to: level - 1)
        }
        if stack.count < level {
          while stack.count < level {
            stack.append(ordered)
            out.append(ordered ? "<ol><li>" : "<ul><li>")
          }
        } else {
          closeLists(to: level)
          out.append("</li><li>")
        }
        out.append(htmlInline(runs))
        continue
      }
      closeLists(to: 0)
      switch block {
      case .heading(let level, let runs): out.append("<h\(level)>\(htmlInline(runs))</h\(level)>")
      case .paragraph(let runs): out.append("<p>\(htmlInline(runs))</p>")
      case .code(let code): out.append("<pre><code>\(Markdown.escape(code))</code></pre>")
      case .table(let rows):
        let body = rows.enumerated().map { i, row in
          let tag = i == 0 ? "th" : "td"
          return "<tr>" + row.map { "<\(tag)>\(Markdown.escape($0))</\(tag)>" }.joined() + "</tr>"
        }.joined()
        out.append("<table>\(body)</table>")
      case .listItem: break
      }
    }
    closeLists(to: 0)
    return out.joined(separator: "\n")
  }

  static func htmlInline(_ runs: [Run]) -> String {
    runs.map { run in
      var s = Markdown.escape(run.text).replacingOccurrences(of: "\n", with: "<br/>")
      if run.code { s = "<code>\(s)</code>" }
      if run.strike { s = "<del>\(s)</del>" }
      if run.italic { s = "<em>\(s)</em>" }
      if run.bold { s = "<strong>\(s)</strong>" }
      if let link = run.link { s = "<a href=\"\(Markdown.escape(link))\">\(s)</a>" }
      return s
    }.joined()
  }
}

/// Carries a value that isn't `Sendable` across one hop between actors, where it's never
/// shared afterwards.
struct UncheckedBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}

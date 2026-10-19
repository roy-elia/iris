import AppKit
import Foundation
import PDFKit
import Vision

/// Runs a macOS command-line tool (zip, ditto, osascript, qlmanage) and collects its output.
enum SystemProcess {
  @discardableResult
  static func run(_ path: String, _ arguments: [String], in directory: URL? = nil) async throws
    -> ToolRunner.Output
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice
    // Both pipes are drained on their own threads, and the exit is observed with a
    // termination handler, so neither a full pipe nor a run loop can stall the wait.
    let collected = UncheckedBox(PipeData())
    let group = DispatchGroup()
    for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
      group.enter()
      DispatchQueue.global().async {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        collected.value.set(data, out: isOut)
        group.leave()
      }
    }
    group.enter()
    process.terminationHandler = { _ in group.leave() }
    try process.run()
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      group.notify(queue: .global()) { done.resume() }
    }
    let stdout = collected.value.out
    let stderr = String(decoding: collected.value.err, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      let name = URL(fileURLWithPath: path).lastPathComponent
      let detail = stderr.split(separator: "\n").suffix(2).joined(separator: " ")
      throw DropError.wrongInput(
        "\(name) failed: \(detail.isEmpty ? "status \(process.terminationStatus)" : detail)")
    }
    return ToolRunner.Output(stdout: stdout, stderr: stderr)
  }

  private final class PipeData: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    var out: Data { lock.withLock { outData } }
    var err: Data { lock.withLock { errData } }
    func set(_ data: Data, out isOut: Bool) {
      lock.withLock {
        if isOut { outData = data } else { errData = data }
      }
    }
  }

  static func scratchDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fdu-doc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}

// MARK: - PDF text

enum PDFText {
  /// The text of every page; pages without selectable text are read with Vision OCR.
  static func attributed(_ doc: PDFDocument, name: String) throws -> NSAttributedString {
    let result = NSMutableAttributedString()
    var found = false
    for index in 0..<doc.pageCount {
      guard let page = doc.page(at: index) else { continue }
      var pageText = page.attributedString ?? NSAttributedString()
      if !pageText.string.contains(where: { !$0.isWhitespace }) {
        pageText = RichText.plain(ocr(page))
      }
      if pageText.string.contains(where: { !$0.isWhitespace }) { found = true }
      if result.length > 0 { result.append(RichText.plain("\n\n")) }
      result.append(pageText)
    }
    guard found else {
      throw DropError.wrongInput("\(name) has no selectable text, and no text was found on its pages.")
    }
    return result
  }

  static func ocr(_ page: PDFPage) -> String {
    guard let image = PDFPageOps.render(page, scale: 2) else { return "" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try? VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
  }
}

// MARK: - PDF pages

public enum PDFPageOps {
  /// Draws a page (with its rotation) on white at `scale` × 72 dpi.
  static func render(_ page: PDFPage, scale: CGFloat, maxPixels: Int = 6000) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    let quarter = page.rotation % 180 != 0
    let size = quarter ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    let s = min(scale, CGFloat(maxPixels) / max(size.width, size.height, 1))
    let w = max(Int((size.width * s).rounded()), 1)
    let h = max(Int((size.height * s).rounded()), 1)
    guard
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: s, y: s)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()
  }

  static func open(_ url: URL) throws -> PDFDocument {
    guard let doc = PDFDocument(url: url) else { throw DropError.readFailed(url.lastPathComponent) }
    if doc.isLocked { throw DropError.wrongInput("\(url.lastPathComponent) is password-protected.") }
    return doc
  }

  /// Saves each page as an image at 144 dpi.
  public static func images(_ source: URL, format: ImageFormat, destinations: (Int) -> URL) throws -> [URL] {
    let doc = try open(source)
    var outputs: [URL] = []
    for index in 0..<doc.pageCount {
      guard let page = doc.page(at: index), let image = render(page, scale: 2) else { continue }
      let out = destinations(index)
      try ImageOps.write(image, as: format, quality: 0.9, to: out)
      outputs.append(out)
    }
    return outputs
  }

  /// Reorders, rotates and drops pages, optionally scaling every page to the same width.
  public static func organize(_ source: URL, plan: PDFPagePlan, destination: URL) throws {
    let doc = try open(source)
    guard !plan.pages.isEmpty else { throw DropError.wrongInput("Keep at least one page.") }
    guard plan.pages.allSatisfy({ $0.index >= 0 && $0.index < doc.pageCount }) else {
      throw DropError.wrongInput("The page list doesn't match \(source.lastPathComponent).")
    }
    if plan.equalWidths {
      try equalWidths(doc, plan: plan, destination: destination)
      return
    }
    let output = PDFDocument()
    for ref in plan.pages {
      guard let page = doc.page(at: ref.index)?.copy() as? PDFPage else { continue }
      page.rotation = (page.rotation + ref.rotation) % 360
      output.insert(page, at: output.pageCount)
    }
    guard output.write(to: destination) else { throw DropError.writeFailed(destination.lastPathComponent) }
  }

  private static func equalWidths(_ doc: PDFDocument, plan: PDFPagePlan, destination: URL) throws {
    var pages: [(PDFPage, CGSize)] = []
    for ref in plan.pages {
      guard let page = doc.page(at: ref.index)?.copy() as? PDFPage else { continue }
      page.rotation = (page.rotation + ref.rotation) % 360
      let b = page.bounds(for: .mediaBox)
      pages.append((page, page.rotation % 180 != 0 ? CGSize(width: b.height, height: b.width) : b.size))
    }
    let width = pages.map(\.1.width).max() ?? 612
    var box = CGRect.zero
    guard let ctx = CGContext(destination as CFURL, mediaBox: &box, nil) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
    for (page, size) in pages {
      let s = width / max(size.width, 1)
      var media = CGRect(x: 0, y: 0, width: width, height: size.height * s)
      let info = [kCGPDFContextMediaBox: Data(bytes: &media, count: MemoryLayout<CGRect>.size)]
      ctx.beginPDFPage(info as CFDictionary)
      ctx.scaleBy(x: s, y: s)
      page.draw(with: .mediaBox, to: ctx)
      ctx.endPDFPage()
    }
    ctx.closePDF()
  }
}

// MARK: - EPUB

public enum EPUBOps {
  /// Limits applied before an EPUB (or any archive) is unpacked.
  static let maxEntries = 20_000
  static let maxUncompressedBytes: Int64 = 2_000_000_000

  /// Reads an EPUB's chapters, in spine order, into attributed text.
  static func read(_ url: URL) async throws -> NSAttributedString {
    let name = url.lastPathComponent
    let dir = try SystemProcess.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try await ArchiveOps.extract(url, into: dir)

    let container = try XMLScan.elements(dir.appendingPathComponent("META-INF/container.xml"))
    guard let opfPath = container.first(where: { $0.name == "rootfile" })?.attributes["full-path"],
      let opf = ArchiveOps.inside(dir, opfPath)
    else { throw DropError.wrongInput("\(name) isn't a valid EPUB (no package file).") }
    let elements = try XMLScan.elements(opf)
    var manifest: [String: (href: String, type: String)] = [:]
    for item in elements where item.name == "item" {
      if let id = item.attributes["id"], let href = item.attributes["href"] {
        manifest[id] = (href.removingPercentEncoding ?? href, item.attributes["media-type"] ?? "")
      }
    }
    let spine = elements.filter { $0.name == "itemref" }.compactMap { $0.attributes["idref"] }
    let base = opf.deletingLastPathComponent()
    let result = NSMutableAttributedString()
    for id in spine {
      guard let item = manifest[id], item.type.contains("html"),
        let file = ArchiveOps.inside(base, item.href)
      else { continue }
      let html = try RichText.readPlainText(file)
      let chapter = try await RichText.readHTML(html, baseURL: file.deletingLastPathComponent())
      if result.length > 0 { result.append(RichText.plain("\n")) }
      result.append(chapter)
    }
    guard result.string.contains(where: { !$0.isWhitespace }) else {
      throw DropError.wrongInput("\(name) has no readable chapters.")
    }
    return result
  }

  /// Writes a reflowable EPUB 3, starting a new chapter at each top-level heading.
  public static func write(_ blocks: [RichText.Block], title: String, to url: URL) throws {
    var chapters: [(title: String, blocks: [RichText.Block])] = []
    for block in blocks {
      if case .heading(1, let runs) = block {
        chapters.append((runs.map(\.text).joined(), [block]))
      } else if chapters.isEmpty {
        chapters.append((title, [block]))
      } else {
        chapters[chapters.count - 1].blocks.append(block)
      }
    }
    let files = chapters.enumerated().map { i, chapter in
      (
        name: "chapter\(i + 1).xhtml", title: chapter.title,
        body: xhtmlPage(title: chapter.title, body: RichText.xhtml(chapter.blocks), css: true)
      )
    }
    let css =
      "body{font-family:serif;line-height:1.5;margin:0 5%}h1,h2,h3{font-family:sans-serif}"
      + "pre{white-space:pre-wrap}table{border-collapse:collapse}td,th{border:1px solid #999;padding:2px 6px}"
    try package(
      title: title, to: url, items: files.map { ($0.name, $0.title, $0.body) },
      extra: [("style.css", "text/css", Data(css.utf8))],
      fixedLayout: false)
  }

  /// Writes a fixed-layout EPUB with one page image per PDF page.
  public static func writeFixed(pdf source: URL, title: String, to url: URL) throws {
    let doc = try PDFPageOps.open(source)
    var items: [(String, String, String)] = []
    var extra: [(String, String, Data)] = []
    for index in 0..<doc.pageCount {
      guard let page = doc.page(at: index), let image = PDFPageOps.render(page, scale: 2, maxPixels: 2000)
      else {
        continue
      }
      let data = NSMutableData()
      guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
        continue
      }
      CGImageDestinationAddImage(
        dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
      CGImageDestinationFinalize(dest)
      let imageName = "page\(index + 1).jpg"
      extra.append((imageName, "image/jpeg", data as Data))
      let body =
        "<div style=\"margin:0;padding:0\"><img src=\"\(imageName)\" alt=\"Page \(index + 1)\" "
        + "style=\"width:\(image.width)px;height:\(image.height)px\"/></div>"
      let pageHTML = xhtmlPage(
        title: "Page \(index + 1)", body: body, css: false,
        viewport: "width=\(image.width), height=\(image.height)")
      items.append(("page\(index + 1).xhtml", "Page \(index + 1)", pageHTML))
    }
    guard !items.isEmpty else { throw DropError.wrongInput("\(source.lastPathComponent) has no pages.") }
    try package(title: title, to: url, items: items, extra: extra, fixedLayout: true)
  }

  static func xhtmlPage(title: String, body: String, css: Bool, viewport: String? = nil) -> String {
    """
    <?xml version="1.0" encoding="utf-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    <head><meta charset="utf-8"/><title>\(Markdown.escape(title))</title>\
    \(viewport.map { "<meta name=\"viewport\" content=\"\($0)\"/>" } ?? "")\
    \(css ? "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>" : "")</head>
    <body>
    \(body)
    </body>
    </html>
    """
  }

  /// Assembles the package: mimetype stored first and uncompressed, then the rest.
  static func package(
    title: String, to url: URL, items: [(name: String, title: String, body: String)],
    extra: [(name: String, type: String, data: Data)], fixedLayout: Bool
  ) throws {
    let dir = try SystemProcess.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let oebps = dir.appendingPathComponent("OEBPS")
    let meta = dir.appendingPathComponent("META-INF")
    try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
    try Data("application/epub+zip".utf8).write(to: dir.appendingPathComponent("mimetype"))
    try Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
      </container>
      """.utf8
    ).write(to: meta.appendingPathComponent("container.xml"))

    for item in items { try Data(item.body.utf8).write(to: oebps.appendingPathComponent(item.name)) }
    for file in extra { try file.data.write(to: oebps.appendingPathComponent(file.name)) }
    let nav = items.map { "<li><a href=\"\($0.name)\">\(Markdown.escape($0.title))</a></li>" }.joined()
    try Data(
      xhtmlPage(
        title: title, body: "<nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1><ol>\(nav)</ol></nav>",
        css: false
      ).utf8
    ).write(to: oebps.appendingPathComponent("nav.xhtml"))

    let manifest =
      ["<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"]
      + items.enumerated().map { i, item in
        "<item id=\"c\(i + 1)\" href=\"\(item.name)\" media-type=\"application/xhtml+xml\"/>"
      }
      + extra.enumerated().map { i, file in
        "<item id=\"x\(i + 1)\" href=\"\(file.name)\" media-type=\"\(file.type)\"/>"
      }
    let spine = items.indices.map { "<itemref idref=\"c\($0 + 1)\"/>" }.joined()
    let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
      of: #"\.\d+"#, with: "", options: .regularExpression)
    let layout =
      fixedLayout
      ? "<meta property=\"rendition:layout\">pre-paginated</meta><meta property=\"rendition:spread\">none</meta>"
      : ""
    let opf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:identifier id="uid">urn:uuid:\(UUID().uuidString.lowercased())</dc:identifier>
      <dc:title>\(Markdown.escape(title))</dc:title>
      <dc:language>\(Locale.current.language.languageCode?.identifier ?? "en")</dc:language>
      <meta property="dcterms:modified">\(modified)</meta>\(layout)
      </metadata>
      <manifest>\(manifest.joined(separator: "\n"))</manifest>
      <spine>\(spine)</spine>
      </package>
      """
    try Data(opf.utf8).write(to: oebps.appendingPathComponent("content.opf"))

    // zip is blocking but quick; run it synchronously here.
    try runZip(["-X0q", url.path, "mimetype"], in: dir)
    try runZip(["-Xr9Dq", url.path, "META-INF", "OEBPS"], in: dir)
  }

  private static func runZip(_ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    p.arguments = args
    p.currentDirectoryURL = dir
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
      throw DropError.writeFailed(URL(fileURLWithPath: args[1]).lastPathComponent)
    }
  }
}

/// A flat list of XML elements and their attributes, namespace prefixes removed.
enum XMLScan {
  struct Element {
    let name: String
    let attributes: [String: String]
  }

  static func elements(_ url: URL) throws -> [Element] {
    guard let parser = XMLParser(contentsOf: url) else { throw DropError.readFailed(url.lastPathComponent) }
    let delegate = Collector()
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else { throw DropError.readFailed(url.lastPathComponent) }
    return delegate.elements
  }

  private final class Collector: NSObject, XMLParserDelegate {
    var elements: [Element] = []

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
      attributes: [String: String] = [:]
    ) {
      let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
      elements.append(Element(name: name, attributes: attributes))
    }
  }
}

// MARK: - Archives

public enum ArchiveOps {
  /// Checks a zip's entries (no absolute paths or "..", sane counts and sizes), then unpacks
  /// it into `directory` with ditto.
  public static func extract(_ zip: URL, into directory: URL) async throws {
    let name = zip.lastPathComponent
    let listing = try? await SystemProcess.run("/usr/bin/zipinfo", ["-1", zip.path])
    guard let listing else { throw DropError.wrongInput("\(name) isn't a zip archive.") }
    let entries = String(decoding: listing.stdout, as: UTF8.self).split(separator: "\n")
    if entries.count > EPUBOps.maxEntries {
      throw DropError.wrongInput("\(name) has too many files to unpack.")
    }
    for entry in entries where !isSafe(String(entry)) {
      throw DropError.wrongInput("\(name) contains a file that would unpack outside its folder.")
    }
    if let totals = try? await SystemProcess.run("/usr/bin/zipinfo", ["-t", zip.path]),
      let bytes = uncompressedBytes(String(decoding: totals.stdout, as: UTF8.self)),
      bytes > EPUBOps.maxUncompressedBytes
    {
      throw DropError.wrongInput("\(name) would unpack to more than 2 GB.")
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try await SystemProcess.run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
  }

  /// Compresses `items` into one zip with ditto, keeping Finder metadata out of the archive.
  /// A single item is stored under its own name; with `contentsOnly`, a single folder's
  /// contents go at the archive's root. Several items are cloned (no extra disk space on APFS)
  /// into a staging folder first, since ditto takes one source.
  public static func zip(_ items: [URL], contentsOnly: Bool = false, destination: URL) async throws {
    guard let first = items.first else { throw DropError.wrongInput("Choose files to compress.") }
    let flags = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn"]
    if items.count == 1 {
      try await SystemProcess.run(
        "/usr/bin/ditto", flags + (contentsOnly ? [] : ["--keepParent"]) + [first.path, destination.path])
      return
    }
    let fm = FileManager.default
    let staging = fm.temporaryDirectory.appendingPathComponent("fdu-zip-\(UUID().uuidString)")
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }
    var used: Set<String> = []
    for item in items {
      // Two items with the same name (from different folders) get "name 2", "name 3", …
      var name = item.lastPathComponent
      var n = 2
      while used.contains(name.lowercased()) {
        let ext = item.pathExtension
        let stem = item.deletingPathExtension().lastPathComponent
        name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
        n += 1
      }
      used.insert(name.lowercased())
      try fm.copyItem(at: item, to: staging.appendingPathComponent(name))
    }
    try await SystemProcess.run("/usr/bin/ditto", flags + [staging.path, destination.path])
  }

  static func isSafe(_ entry: String) -> Bool {
    if entry.hasPrefix("/") || entry.hasPrefix("\\") { return false }
    let parts = entry.split(whereSeparator: { $0 == "/" || $0 == "\\" })
    return !parts.contains("..")
  }

  /// Parses "3 files, 1234 bytes uncompressed, …" from `zipinfo -t`.
  static func uncompressedBytes(_ s: String) -> Int64? {
    guard let re = try? NSRegularExpression(pattern: #"(\d+) bytes uncompressed"#),
      let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
      let r = Range(m.range(at: 1), in: s)
    else { return nil }
    return Int64(s[r])
  }

  /// `relative` resolved inside `base`, or nil if it would leave it (including via links).
  static func inside(_ base: URL, _ relative: String) -> URL? {
    let url = base.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
    let root = base.standardizedFileURL.resolvingSymlinksInPath().path
    guard url.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url
  }
}

// MARK: - Clippings

enum ClippingOps {
  /// Reads a Finder text clipping (a property list of pasteboard types).
  static func read(_ url: URL) throws -> NSAttributedString {
    let name = url.lastPathComponent
    guard let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let types = plist["UTI-Data"] as? [String: Any]
    else { throw DropError.wrongInput("\(name) isn't a text clipping this Mac can read.") }
    for key in ["public.rtf", "com.apple.flat-rtfd"] {
      if let rtf = types[key] as? Data,
        let text = try? NSAttributedString(data: rtf, options: [:], documentAttributes: nil)
      {
        return text
      }
    }
    for key in ["public.utf8-plain-text", "public.plain-text", "public.utf16-plain-text"] {
      if let text = types[key] as? String { return RichText.plain(text) }
      if let data = types[key] as? Data, let text = String(data: data, encoding: .utf8) {
        return RichText.plain(text)
      }
    }
    throw DropError.wrongInput("\(name) has no text in it.")
  }
}

// MARK: - Tables

enum TableOps {
  /// Parses CSV (or TSV) with quoted fields.
  static func parse(_ text: String, separator: Character) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
    if chars.first == "\u{FEFF}" { chars.removeFirst() }
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if quoted {
        if c == "\"" {
          if i + 1 < chars.count, chars[i + 1] == "\"" {
            field.append("\"")
            i += 1
          } else {
            quoted = false
          }
        } else {
          field.append(c)
        }
      } else if c == "\"" && field.isEmpty {
        quoted = true
      } else if c == separator {
        row.append(field)
        field = ""
      } else if c == "\n" || c == "\r" {
        row.append(field)
        rows.append(row)
        row = []
        field = ""
      } else {
        field.append(c)
      }
      i += 1
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }

  static func html(_ rows: [[String]], title: String) -> String {
    let body = rows.enumerated().map { i, row in
      let tag = i == 0 ? "th" : "td"
      return "<tr>" + row.map { "<\(tag)>\(Markdown.escape($0))</\(tag)>" }.joined() + "</tr>"
    }.joined()
    return """
      <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(Markdown.escape(title))</title></head>
      <body><table border="1" cellpadding="4" cellspacing="0">\(body)</table></body></html>
      """
  }
}

// MARK: - Subtitles

public struct SubtitleCue: Equatable, Sendable {
  public var start: Double
  public var end: Double
  public var text: String
}

public enum SubtitleOps {
  public static func parse(_ text: String) -> [SubtitleCue] {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\u{FEFF}", with: "")
    var cues: [SubtitleCue] = []
    for chunk in normalized.components(separatedBy: "\n\n") {
      let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
      let parts = lines[timing].components(separatedBy: "-->")
      guard parts.count == 2, let start = time(parts[0]),
        let end = time(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
      else { continue }
      let body = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard !body.isEmpty, end > start else { continue }
      cues.append(SubtitleCue(start: start, end: end, text: body))
    }
    return cues
  }

  /// "01:02:03,456", "01:02:03.456" or "02:03.456".
  static func time(_ s: String) -> Double? {
    let parts = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
      .split(separator: ":").map(String.init)
    guard (2...3).contains(parts.count), let seconds = Double(parts.last!) else { return nil }
    let numbers = parts.dropLast().compactMap { Int($0) }
    guard numbers.count == parts.count - 1 else { return nil }
    return numbers.reduce(0) { $0 * 60 + Double($1) } * 60 + seconds
  }

  static func stamp(_ t: Double, separator: String) -> String {
    let ms = Int((t * 1000).rounded())
    return String(
      format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, separator, ms % 1000)
  }

  public static func write(_ cues: [SubtitleCue], as format: SubtitleFormat) -> String {
    switch format {
    case .srt:
      return cues.enumerated().map { i, c in
        "\(i + 1)\n\(stamp(c.start, separator: ",")) --> \(stamp(c.end, separator: ","))\n\(stripVTTTags(c.text))"
      }.joined(separator: "\n\n") + "\n"
    case .vtt:
      return "WEBVTT\n\n"
        + cues.map { c in "\(stamp(c.start, separator: ".")) --> \(stamp(c.end, separator: "."))\n\(c.text)" }
        .joined(separator: "\n\n") + "\n"
    }
  }

  /// SRT players show `<v Name>` voice tags literally; keep the basic styling tags only.
  static func stripVTTTags(_ s: String) -> String {
    guard let re = try? NSRegularExpression(pattern: #"</?(v|c|lang|ruby|rt)(\.[^ >]*)?( [^>]*)?>"#) else {
      return s
    }
    return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
  }

  public static func convert(_ source: URL, to format: SubtitleFormat, destination: URL) throws {
    let cues = parse(try RichText.readPlainText(source))
    guard !cues.isEmpty else {
      throw DropError.wrongInput("No valid subtitle cues were found in \(source.lastPathComponent).")
    }
    try write(cues, as: format).write(to: destination, atomically: true, encoding: .utf8)
  }
}

// MARK: - iWork

public enum IWorkOps {
  /// The PDF preview saved inside a Pages, Keynote or Numbers document, when it has one.
  static func previewPDF(of url: URL) throws -> PDFDocument {
    let names = ["QuickLook/Preview.pdf", "preview.pdf", "Preview.pdf"]
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    if isDir.boolValue {
      for n in names {
        if let doc = PDFDocument(url: url.appendingPathComponent(n)) { return doc }
      }
    } else {
      for n in names {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path, n]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { continue }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0, let doc = PDFDocument(data: data) { return doc }
      }
    }
    throw DropError.wrongInput(
      "\(url.lastPathComponent) has no saved preview. Opening it needs Pages, Keynote or Numbers.")
  }

  /// AppleScript that opens argv[1] in `app` and exports it to argv[2] as PDF.
  static func exportScript(_ app: IWorkApp) -> [String] {
    [
      "on run argv",
      "tell application id \"\(app.bundleID)\"",
      "set d to open (POSIX file (item 1 of argv))",
      "export d to (POSIX file (item 2 of argv)) as PDF",
      "close d saving no",
      "end tell",
      "end run",
    ]
  }

  /// A presentation, spreadsheet or iWork document as PDF: exported by its app when it's
  /// installed, otherwise the document's saved preview or a Quick Look rendering.
  public static func exportPDF(_ source: URL, app: IWorkApp?, destination: URL) async throws {
    if let app, app.isInstalled {
      let args = exportScript(app).flatMap { ["-e", $0] } + [source.path, destination.path]
      try await SystemProcess.run("/usr/bin/osascript", args)
      return
    }
    if let preview = try? previewPDF(of: source), preview.write(to: destination) { return }
    // Quick Look renders the first page or sheet.
    let dir = try SystemProcess.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try? await SystemProcess.run("/usr/bin/qlmanage", ["-t", "-s", "2000", "-o", dir.path, source.path])
    let pngs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    guard let png = pngs.first(where: { $0.pathExtension == "png" }) else {
      let needed = app?.rawValue ?? "Pages"
      throw DropError.wrongInput("\(source.lastPathComponent) needs \(needed) to convert.")
    }
    try PDFOps.imagesToPDF([png], destination: destination)
  }

  /// A native Pages document, made by Pages from a temporary Word file.
  static func writePages(_ text: NSAttributedString, to url: URL) async throws {
    guard IWorkApp.pages.isInstalled else {
      throw DropError.wrongInput("Making Pages documents needs Pages.")
    }
    let dir = try SystemProcess.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let docx = dir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).docx")
    try text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
    ).write(to: docx)
    let script = [
      "on run argv",
      "tell application id \"\(IWorkApp.pages.bundleID)\"",
      "set d to open (POSIX file (item 1 of argv))",
      "save d in (POSIX file (item 2 of argv))",
      "close d saving no",
      "end tell",
      "end run",
    ]
    try await SystemProcess.run("/usr/bin/osascript", script.flatMap { ["-e", $0] } + [docx.path, url.path])
  }
}

// MARK: - Conversion

public enum DocumentOps {
  /// Converts one document, PDF, table or presentation.
  public static func convert(_ file: DroppedFile, to output: DocumentOutput, destination: URL) async throws {
    let title = file.url.deletingPathExtension().lastPathComponent
    switch (file.kind, output) {
    case (.office(let format), .pdf) where !format.isTable:
      try await IWorkOps.exportPDF(file.url, app: format.app, destination: destination)
    case (.document(.pages), .pdf):
      try await IWorkOps.exportPDF(
        file.url, app: IWorkApp.pages.isInstalled ? .pages : nil, destination: destination)
    case (.pdf, .epubFixed):
      try EPUBOps.writeFixed(pdf: file.url, title: title, to: destination)
    case (.document(.md), .html):
      let page = Markdown.page(try RichText.readPlainText(file.url), title: title)
      try page.write(to: destination, atomically: true, encoding: .utf8)
    default:
      let text = try await RichText.load(file.url, kind: file.kind)
      try await RichText.write(text, as: output, title: title, to: destination)
    }
    guard FileManager.default.fileExists(atPath: destination.path) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// Unzips next to the archive, into a folder named after it.
  public static func extract(_ zip: URL, into folder: URL) async throws {
    do {
      try await ArchiveOps.extract(zip, into: folder)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }

  /// Whether `file` can be converted to `output`, or why not.
  public static func problem(_ kind: FileKind, output: DocumentOutput) -> String? {
    switch kind {
    case .pdf:
      if output == .pdf { return "It's already a PDF." }
    case .office(let format):
      if !format.isTable && output != .pdf { return "Presentations and spreadsheets convert to PDF." }
      if output == .epubFixed { return "Page-image EPUBs are made from PDFs." }
    case .document:
      if output == .epubFixed { return "Page-image EPUBs are made from PDFs." }
    default:
      return "Not a document."
    }
    return nil
  }
}

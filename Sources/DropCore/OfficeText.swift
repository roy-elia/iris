import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

/// Text read from presentations, spreadsheets and images, so they convert to the same text
/// outputs (TXT, Markdown, HTML, Word, RTF, EPUB, Pages) as documents do.
enum OfficeText {
  /// A deck's text, one "Slide N" heading per slide. PowerPoint files are read from their
  /// XML; Keynote and .ppt decks (or a .pptx with no text runs) are exported to PDF first.
  static func presentation(_ url: URL, format: OfficeFormat) async throws -> NSAttributedString {
    let name = url.lastPathComponent
    if format == .pptx, let slides = try? await pptxSlides(url), slides.contains(where: { !$0.isEmpty }) {
      let html = slides.enumerated().map { i, paragraphs in
        "<h2>Slide \(i + 1)</h2>" + paragraphs.map { "<p>\(Markdown.escape($0))</p>" }.joined()
      }.joined()
      return try await RichText.readHTML(
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(html)</body></html>", baseURL: nil)
    }
    let dir = try SystemProcess.scratchDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("slides.pdf")
    try await IWorkOps.exportPDF(url, app: format.app, powerPoint: format.powerPointExports, destination: pdf)
    guard let doc = PDFDocument(url: pdf) else { throw DropError.readFailed(name) }
    return try PDFText.attributed(doc, name: name)
  }

  /// Each slide's paragraphs, in slide order (ppt/slides/slide1.xml, slide2.xml, ...).
  static func pptxSlides(_ url: URL) async throws -> [[String]] {
    let listing = try await SystemProcess.run("/usr/bin/unzip", ["-Z1", url.path])
    let entries = String(decoding: listing.stdout, as: UTF8.self).split(separator: "\n").map(String.init)
    let numbered = entries.compactMap { entry -> (Int, String)? in
      guard entry.hasPrefix("ppt/slides/slide"), entry.hasSuffix(".xml") else { return nil }
      let digits = entry.dropFirst("ppt/slides/slide".count).dropLast(".xml".count)
      return Int(digits).map { ($0, entry) }
    }.sorted { $0.0 < $1.0 }
    guard !numbered.isEmpty else { throw DropError.readFailed(url.lastPathComponent) }
    var slides: [[String]] = []
    for (_, entry) in numbered {
      let data = try await SpreadsheetOps.zipEntry(url, entry) ?? Data()
      slides.append(DrawingMLText().paragraphs(data))
    }
    return slides
  }

  /// A workbook's sheets as headed tables.
  static func spreadsheet(_ url: URL, format: OfficeFormat) async throws -> NSAttributedString {
    let sheets = try await SpreadsheetOps.read(url, format: format).filter { !$0.isEmpty }
    guard !sheets.isEmpty else { throw DropError.wrongInput("\(url.lastPathComponent) has no cells.") }
    return try await RichText.readHTML(
      SpreadsheetOps.html(sheets, title: url.lastPathComponent), baseURL: nil)
  }

  /// The text in a picture, read with Vision OCR, one line per recognised line.
  static func image(_ url: URL) throws -> NSAttributedString {
    let name = url.lastPathComponent
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw DropError.readFailed(name) }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try? VNImageRequestHandler(cgImage: image).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    guard !lines.isEmpty else { throw DropError.wrongInput("No text was found in \(name).") }
    return RichText.plain(lines.joined(separator: "\n"))
  }
}

/// Collects the text of DrawingML paragraphs (<a:p> holding <a:t> runs), as in PowerPoint slides.
final class DrawingMLText: NSObject, XMLParserDelegate {
  private var paragraphs: [String] = []
  private var current: String?
  private var inText = false

  func paragraphs(_ data: Data) -> [String] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.parse()
    return paragraphs
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
    attributes: [String: String] = [:]
  ) {
    switch elementName {
    case "a:p": current = ""
    case "a:t": inText = true
    case "a:br": current? += "\n"
    default: break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if inText { current? += string }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
  ) {
    switch elementName {
    case "a:t": inText = false
    case "a:p":
      if let text = current?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
        paragraphs.append(text)
      }
      current = nil
    default: break
    }
  }
}

extension SpreadsheetOps {
  /// Saves every non-empty sheet as JSON (one object per row, keyed by the header row) or
  /// vCard. `destination` gets the sheet's name when there's more than one sheet, else nil.
  public static func exportData(
    _ source: URL, format: OfficeFormat, to output: DataFormat, destination: (String?) -> URL
  ) async throws -> [URL] {
    let name = source.lastPathComponent
    let sheets = try await read(source, format: format).filter { !$0.isEmpty }
    guard !sheets.isEmpty else { throw DropError.wrongInput("\(name) has no cells to save.") }
    var outputs: [URL] = []
    for sheet in sheets {
      let csv = DataOps.csv(padded(sheet.rows))
      let data: Data
      switch output {
      case .json: data = try DataOps.csvToJSON(csv)
      case .vcf: data = Data(try DataOps.csvToVCard(csv, name: name).utf8)
      case .csv: data = Data(csv.utf8)
      default: throw DropError.wrongInput("\(name) can't be converted to \(output.displayName).")
      }
      let out = destination(sheets.count == 1 ? nil : fileSafe(sheet.name))
      try data.write(to: out, options: .atomic)
      outputs.append(out)
    }
    return outputs
  }
}

/// LibreOffice, used headless to read workbooks that Numbers can't open or isn't there for.
public enum LibreOffice {
  public static let bundleID = "org.libreoffice.script"

  /// The `soffice` command inside LibreOffice.app, when it's installed.
  public static var executable: String? {
    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let path = app.appendingPathComponent("Contents/MacOS/soffice").path
    return FileManager.default.isExecutableFile(atPath: path) ? path : nil
  }

  public static var isInstalled: Bool { executable != nil }

  /// Converts `source` to an Excel workbook in `folder` and returns it. A private profile
  /// keeps a LibreOffice window the person has open from blocking the headless run.
  static func convertToXLSX(_ source: URL, in folder: URL) async throws -> URL {
    guard let soffice = executable else {
      throw DropError.wrongInput("Reading \(source.lastPathComponent) needs Numbers or LibreOffice.")
    }
    let profile = folder.appendingPathComponent("profile", isDirectory: true)
    try await SystemProcess.run(
      soffice,
      [
        "-env:UserInstallation=\(profile.absoluteString)", "--headless", "--norestore",
        "--convert-to", "xlsx", "--outdir", folder.path, source.path,
      ], timeout: 120)
    let out = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".xlsx")
    guard FileManager.default.fileExists(atPath: out.path) else {
      throw DropError.wrongInput("LibreOffice couldn't open \(source.lastPathComponent).")
    }
    return out
  }
}

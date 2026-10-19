import Foundation

/// One sheet of a workbook, as rows of displayed cell text.
public struct Sheet: Equatable, Sendable {
  public var name: String
  public var rows: [[String]]

  public init(name: String, rows: [[String]]) {
    self.name = name
    self.rows = rows
  }

  public var isEmpty: Bool { rows.allSatisfy { $0.allSatisfy(\.isEmpty) } }
}

/// Reads Excel (.xlsx) and OpenDocument (.ods) workbooks from their XML, and saves each
/// sheet as CSV. Numbers and legacy .xls files are first exported to .xlsx by Numbers.
public enum SpreadsheetOps {
  /// Spreadsheet formats `csv` reads.
  public static func canRead(_ format: OfficeFormat) -> Bool {
    switch format {
    case .xlsx, .ods: true
    case .numbers, .xls: IWorkApp.numbers.isInstalled
    default: false
    }
  }

  /// Why `format` can't be saved as CSV on this Mac, if it can't.
  public static func problem(_ format: OfficeFormat) -> String? {
    switch format {
    case .xlsx, .ods: nil
    case .numbers, .xls: IWorkApp.numbers.isInstalled ? nil : "Needs Numbers"
    default: "Spreadsheets only"
    }
  }

  /// Saves every non-empty sheet as CSV. `destination` gets the sheet's name when the
  /// workbook has more than one sheet with cells, else nil.
  public static func exportCSV(
    _ source: URL, format: OfficeFormat, destination: (String?) -> URL
  ) async throws -> [URL] {
    let sheets = try await read(source, format: format).filter { !$0.isEmpty }
    guard !sheets.isEmpty else {
      throw DropError.wrongInput("\(source.lastPathComponent) has no cells to save.")
    }
    var outputs: [URL] = []
    for sheet in sheets {
      let out = destination(sheets.count == 1 ? nil : fileSafe(sheet.name))
      try Data(DataOps.csv(padded(sheet.rows)).utf8).write(to: out, options: .atomic)
      outputs.append(out)
    }
    return outputs
  }

  /// The workbook's sheets, in order.
  public static func read(_ source: URL, format: OfficeFormat) async throws -> [Sheet] {
    let name = source.lastPathComponent
    switch format {
    case .xlsx:
      return try await xlsx(source, name: name)
    case .ods:
      guard let content = try await zipEntry(source, "content.xml") else {
        throw DropError.readFailed(name)
      }
      return try ods(content, name: name)
    case .numbers, .xls:
      guard IWorkApp.numbers.isInstalled else {
        throw DropError.wrongInput("Saving \(format.displayName) sheets as CSV needs Numbers.")
      }
      let dir = try SystemProcess.scratchDirectory()
      defer { try? FileManager.default.removeItem(at: dir) }
      let book = dir.appendingPathComponent("book.xlsx")
      let args = excelExportScript().flatMap { ["-e", $0] } + [source.path, book.path]
      try await SystemProcess.run("/usr/bin/osascript", args)
      return try await xlsx(book, name: name)
    default:
      throw DropError.wrongInput("\(name) isn't a spreadsheet.")
    }
  }

  /// AppleScript that opens argv[1] in Numbers and saves it to argv[2] as an Excel workbook.
  static func excelExportScript() -> [String] {
    [
      "on run argv",
      "tell application id \"\(IWorkApp.numbers.bundleID)\"",
      "set d to open (POSIX file (item 1 of argv))",
      "export d to (POSIX file (item 2 of argv)) as Microsoft Excel",
      "close d saving no",
      "end tell",
      "end run",
    ]
  }

  /// The workbook's sheets as a PDF of tables, each headed by its sheet name. Used when
  /// neither Numbers nor Quick Look can render the file.
  public static func renderPDF(_ source: URL, format: OfficeFormat, to destination: URL) async throws {
    let sheets = try await read(source, format: format).filter { !$0.isEmpty }
    guard !sheets.isEmpty else {
      throw DropError.wrongInput("\(source.lastPathComponent) has no cells to save.")
    }
    let text = try await RichText.readHTML(html(sheets, title: source.lastPathComponent), baseURL: nil)
    try RichText.renderPDF(text, to: destination)
  }

  static func html(_ sheets: [Sheet], title: String) -> String {
    let body = sheets.map { sheet in
      let rows = padded(sheet.rows).enumerated().map { i, row in
        let tag = i == 0 ? "th" : "td"
        return "<tr>" + row.map { "<\(tag)>\(Markdown.escape($0))</\(tag)>" }.joined() + "</tr>"
      }.joined()
      return
        "<h2>\(Markdown.escape(sheet.name))</h2><table border=\"1\" cellpadding=\"4\" cellspacing=\"0\">\(rows)</table>"
    }.joined()
    return
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(Markdown.escape(title))</title></head>"
      + "<body>\(body)</body></html>"
  }

  // MARK: Helpers

  /// Rows padded to the widest one, so every CSV line has the same number of fields.
  static func padded(_ rows: [[String]]) -> [[String]] {
    let width = rows.map(\.count).max() ?? 0
    return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
  }

  /// A sheet name usable in a file name.
  static func fileSafe(_ name: String) -> String {
    let cleaned = name.map { "/:\\".contains($0) ? "-" : $0 }
    let text = String(cleaned).trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? "Sheet" : text
  }

  /// One file from a zip archive, or nil when it isn't there.
  static func zipEntry(_ archive: URL, _ entry: String) async throws -> Data? {
    let output = try? await SystemProcess.run("/usr/bin/unzip", ["-p", archive.path, entry])
    guard let data = output?.stdout, !data.isEmpty else { return nil }
    return data
  }

  /// Zero-based column index from a cell reference such as "AB12".
  static func column(of reference: String) -> Int? {
    var index = 0
    var sawLetter = false
    for scalar in reference.unicodeScalars {
      guard (65...90).contains(scalar.value) || (97...122).contains(scalar.value) else { break }
      index = index * 26 + Int((scalar.value & ~32) - 64)
      sawLetter = true
    }
    return sawLetter ? index - 1 : nil
  }

  /// One-based row number from a cell reference such as "AB12".
  static func row(of reference: String) -> Int? {
    Int(String(reference.drop { !$0.isNumber }))
  }

  // MARK: XLSX

  static func xlsx(_ url: URL, name: String) async throws -> [Sheet] {
    guard let workbook = try await zipEntry(url, "xl/workbook.xml") else {
      throw DropError.wrongInput("\(name) isn't a readable Excel workbook.")
    }
    let rels = try await zipEntry(url, "xl/_rels/workbook.xml.rels") ?? Data()
    let shared = try await zipEntry(url, "xl/sharedStrings.xml").map(sharedStrings) ?? []
    let targets = relationshipTargets(rels)
    var sheets: [Sheet] = []
    for (index, entry) in workbookSheets(workbook).enumerated() {
      let path = targets[entry.relationship].map(partPath) ?? "xl/worksheets/sheet\(index + 1).xml"
      guard let xml = try await zipEntry(url, path) else { continue }
      sheets.append(Sheet(name: entry.name, rows: worksheetRows(xml, shared: shared)))
    }
    return sheets
  }

  /// A relationship target as a path inside the archive.
  static func partPath(_ target: String) -> String {
    target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
  }

  static func workbookSheets(_ data: Data) -> [(name: String, relationship: String)] {
    let reader = XMLWalker()
    var sheets: [(String, String)] = []
    reader.onStart = { element, attributes in
      guard element == "sheet" else { return }
      let rel = attributes.first { $0.key == "r:id" || $0.key.hasSuffix(":id") }?.value ?? ""
      sheets.append((attributes["name"] ?? "Sheet \(sheets.count + 1)", rel))
    }
    reader.parse(data)
    return sheets
  }

  static func relationshipTargets(_ data: Data) -> [String: String] {
    let reader = XMLWalker()
    var targets: [String: String] = [:]
    reader.onStart = { element, attributes in
      if element == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
        targets[id] = target
      }
    }
    reader.parse(data)
    return targets
  }

  /// The shared string table. Phonetic runs (`rPh`) are left out, as Excel shows them.
  static func sharedStrings(_ data: Data) -> [String] {
    let reader = XMLWalker()
    var strings: [String] = []
    var current = ""
    var inItem = false
    var inText = false
    var phonetic = 0
    reader.onStart = { element, _ in
      switch element {
      case "si": (inItem, current) = (true, "")
      case "rPh": phonetic += 1
      case "t": inText = inItem && phonetic == 0
      default: break
      }
    }
    reader.onText = { if inText { current += $0 } }
    reader.onEnd = { element in
      switch element {
      case "si":
        strings.append(current)
        inItem = false
      case "rPh": phonetic -= 1
      case "t": inText = false
      default: break
      }
    }
    reader.parse(data)
    return strings
  }

  static func worksheetRows(_ data: Data, shared: [String]) -> [[String]] {
    let reader = XMLWalker()
    var rows: [[String]] = []
    var row: [String] = []
    var rowNumber = 0
    var cellColumn = 0
    var cellType = ""
    var value = ""
    var inline = ""
    var capture: String?
    reader.onStart = { element, attributes in
      switch element {
      case "row":
        rowNumber = attributes["r"].flatMap(Int.init) ?? rowNumber + 1
        row = []
      case "c":
        cellColumn = attributes["r"].flatMap(column) ?? row.count
        cellType = attributes["t"] ?? "n"
        (value, inline) = ("", "")
      case "v": capture = "v"
      case "t" where cellType == "inlineStr": capture = "t"
      default: break
      }
    }
    reader.onText = { text in
      if capture == "v" { value += text } else if capture == "t" { inline += text }
    }
    reader.onEnd = { element in
      switch element {
      case "v", "t": capture = nil
      case "c":
        let text: String
        switch cellType {
        case "s": text = Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? ""
        case "inlineStr": text = inline
        case "b": text = value == "1" ? "TRUE" : value == "0" ? "FALSE" : value
        default: text = value
        }
        guard !text.isEmpty, cellColumn < 16_384 else { return }
        if row.count <= cellColumn { row += Array(repeating: "", count: cellColumn + 1 - row.count) }
        row[cellColumn] = text
      case "row":
        guard !row.isEmpty, rowNumber <= 1_048_576 else { return }
        while rows.count < rowNumber - 1 { rows.append([]) }
        rows.append(row)
      default: break
      }
    }
    reader.parse(data)
    return rows
  }

  // MARK: ODS

  /// Sheets from an OpenDocument `content.xml`. Repeated empty rows and cells at the end
  /// of a sheet (spreadsheets pad to the full grid this way) are dropped.
  static func ods(_ data: Data, name: String) throws -> [Sheet] {
    let reader = XMLWalker()
    let maxRepeat = 1_000
    var sheets: [Sheet] = []
    var rows: [[String]] = []
    var sheetName = ""
    var row: [String] = []
    var rowRepeat = 1
    var pendingRows = 0
    var pendingCells = 0
    var cellRepeat = 1
    var cellValue = ""
    var paragraphs: [String] = []
    var paragraph = ""
    var paragraphDepth = 0
    var annotation = 0
    var inCell = false
    var tableDepth = 0
    reader.onStart = { element, attributes in
      switch element {
      case "table:table":
        tableDepth += 1
        guard tableDepth == 1 else { return }
        sheetName = attributes["table:name"] ?? "Sheet \(sheets.count + 1)"
        (rows, pendingRows) = ([], 0)
      case "table:table-row" where tableDepth == 1:
        rowRepeat = attributes["table:number-rows-repeated"].flatMap(Int.init) ?? 1
        (row, pendingCells) = ([], 0)
      case "table:table-cell" where tableDepth == 1, "table:covered-table-cell" where tableDepth == 1:
        inCell = true
        cellRepeat = attributes["table:number-columns-repeated"].flatMap(Int.init) ?? 1
        cellValue = attributes["office:value"] ?? attributes["office:date-value"] ?? ""
        if let bool = attributes["office:boolean-value"] { cellValue = bool.uppercased() }
        paragraphs = []
      case "office:annotation": annotation += 1
      case "text:p", "text:h":
        if inCell && annotation == 0 {
          paragraphDepth += 1
          if paragraphDepth == 1 { paragraph = "" }
        }
      case "text:s" where paragraphDepth > 0 && annotation == 0:
        paragraph += String(repeating: " ", count: attributes["text:c"].flatMap(Int.init) ?? 1)
      case "text:tab" where paragraphDepth > 0 && annotation == 0: paragraph += "\t"
      case "text:line-break" where paragraphDepth > 0 && annotation == 0: paragraph += "\n"
      default: break
      }
    }
    reader.onText = { text in
      if paragraphDepth > 0 && annotation == 0 { paragraph += text }
    }
    reader.onEnd = { element in
      switch element {
      case "office:annotation": annotation -= 1
      case "text:p", "text:h":
        guard paragraphDepth > 0, annotation == 0 else { return }
        paragraphDepth -= 1
        if paragraphDepth == 0 { paragraphs.append(paragraph) }
      case "table:table-cell" where tableDepth == 1, "table:covered-table-cell" where tableDepth == 1:
        inCell = false
        let text = paragraphs.isEmpty ? cellValue : paragraphs.joined(separator: "\n")
        if text.isEmpty {
          pendingCells += cellRepeat
        } else {
          row += Array(repeating: "", count: min(pendingCells, 16_384))
          row += Array(repeating: text, count: min(cellRepeat, maxRepeat))
          pendingCells = 0
        }
      case "table:table-row" where tableDepth == 1:
        if row.isEmpty {
          pendingRows += rowRepeat
        } else {
          rows += Array(repeating: [], count: min(pendingRows, 1_048_576))
          rows += Array(repeating: row, count: min(rowRepeat, maxRepeat))
          pendingRows = 0
        }
      case "table:table":
        tableDepth -= 1
        if tableDepth == 0 { sheets.append(Sheet(name: sheetName, rows: rows)) }
      default: break
      }
    }
    guard reader.parse(data) else { throw DropError.readFailed(name) }
    return sheets
  }
}

/// A small callback wrapper around `XMLParser`. Element names keep their prefix
/// ("table:table"), except in the spreadsheetML namespace, whose prefix is dropped.
final class XMLWalker: NSObject, XMLParserDelegate {
  var onStart: (String, [String: String]) -> Void = { _, _ in }
  var onEnd: (String) -> Void = { _ in }
  var onText: (String) -> Void = { _ in }

  @discardableResult
  func parse(_ data: Data) -> Bool {
    let parser = XMLParser(data: data)
    parser.delegate = self
    return parser.parse()
  }

  /// "x:c" → "c" for Excel parts, which some writers save with a prefix. ODS names
  /// ("table:", "text:", "office:") are kept so they stay unambiguous.
  private func name(_ qualified: String) -> String {
    guard let colon = qualified.firstIndex(of: ":") else { return qualified }
    let prefix = qualified[..<colon]
    if ["table", "text", "office"].contains(prefix) { return qualified }
    return String(qualified[qualified.index(after: colon)...])
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
  ) {
    onStart(name(elementName), attributeDict)
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    onEnd(name(elementName))
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) { onText(string) }
}

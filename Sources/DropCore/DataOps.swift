import Foundation

/// Structured data files: JSON, XML, property lists, vCards and CSV tables.
public enum DataFormat: String, CaseIterable, Codable, Sendable {
  case json, csv, xml, plist, vcf

  public var fileExtension: String { rawValue }

  public var displayName: String {
    switch self {
    case .vcf: "vCard"
    case .plist: "Plist"
    default: rawValue.uppercased()
    }
  }

  /// Input formats: JSON, XML, plist and vCard files (CSV is read as a table document).
  public init?(fileExtension ext: String) {
    switch ext.lowercased() {
    case "json": self = .json
    case "xml": self = .xml
    case "plist": self = .plist
    case "vcf", "vcard": self = .vcf
    default: return nil
    }
  }

  /// What a file of this format converts to.
  public var outputs: [DataFormat] {
    switch self {
    case .json: [.csv, .xml, .plist]
    case .csv: [.json, .vcf]
    case .xml, .plist: [.json]
    case .vcf: [.csv]
    }
  }

  /// The data format of `url`, CSV included.
  public static func of(_ url: URL) -> DataFormat? {
    ["csv", "tsv"].contains(url.pathExtension.lowercased())
      ? .csv : DataFormat(fileExtension: url.pathExtension)
  }
}

/// Converts between data formats with Foundation only.
public enum DataOps {
  public static func convert(_ source: URL, to output: DataFormat, destination: URL) throws {
    let name = source.lastPathComponent
    guard let input = DataFormat.of(source), input.outputs.contains(output) else {
      throw DropError.wrongInput("\(name) can't be converted to \(output.displayName).")
    }
    var data = try Data(contentsOf: source)
    if source.pathExtension.lowercased() == "tsv" {
      // Tab-separated tables are read as CSV.
      data = Data(csv(TableOps.parse(try text(data, name: name), separator: "\t")).utf8)
    }
    let result: Data
    switch (input, output) {
    case (.json, .csv): result = Data(try jsonToCSV(data, name: name).utf8)
    case (.json, .xml): result = Data(try jsonToXML(data, name: name).utf8)
    case (.json, .plist): result = try jsonToPlist(data, name: name)
    case (.csv, .json): result = try csvToJSON(text(data, name: name))
    case (.csv, .vcf): result = Data(try csvToVCard(text(data, name: name), name: name).utf8)
    case (.xml, .json): result = try xmlToJSON(data, name: name)
    case (.plist, .json): result = try plistToJSON(data, name: name)
    case (.vcf, .csv): result = Data(try vCardToCSV(text(data, name: name), name: name).utf8)
    default: throw DropError.wrongInput("\(name) can't be converted to \(output.displayName).")
    }
    try result.write(to: destination, options: .atomic)
  }

  static func text(_ data: Data, name: String) throws -> String {
    try SubtitleOps.decode(data, name: name)
  }

  // MARK: JSON ↔ CSV

  /// An array of objects (top-level, or the first array found in a top-level object) as a
  /// table: one column per key, in first-seen order. Nested objects flatten to "a.b"
  /// columns; arrays are written as JSON.
  static func jsonToCSV(_ data: Data, name: String) throws -> String {
    let root = try parseJSON(data, name: name)
    let records: [Any]
    if let array = root as? [Any] {
      records = array
    } else if let object = root as? [String: Any] {
      records = object.keys.sorted().lazy.compactMap { object[$0] as? [Any] }.first ?? [object]
    } else {
      throw DropError.wrongInput("\(name) holds a single value, not a list of records.")
    }
    var columns: [String] = []
    var seen: Set<String> = []
    let rows: [[String: String]] = records.map { record in
      var flat: [String: String] = [:]
      flatten(record, prefix: "", into: &flat, order: &columns, seen: &seen)
      return flat
    }
    guard !columns.isEmpty else { throw DropError.wrongInput("\(name) has no records to put in a table.") }
    return csv([columns] + rows.map { row in columns.map { row[$0] ?? "" } })
  }

  private static func flatten(
    _ value: Any, prefix: String, into flat: inout [String: String], order: inout [String],
    seen: inout Set<String>
  ) {
    if let object = value as? [String: Any] {
      // JSONSerialization loses key order; sort for a stable layout.
      for key in object.keys.sorted() {
        flatten(
          object[key]!, prefix: prefix.isEmpty ? key : "\(prefix).\(key)", into: &flat, order: &order,
          seen: &seen)
      }
      return
    }
    let key = prefix.isEmpty ? "value" : prefix
    if seen.insert(key).inserted { order.append(key) }
    flat[key] = scalarText(value)
  }

  static func scalarText(_ value: Any) -> String {
    switch value {
    case is NSNull: return ""
    case let s as String: return s
    case let n as NSNumber:
      return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
    default:
      let data =
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]))
      return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
  }

  /// The header row names the keys; every value stays a string, so nothing is reinterpreted.
  static func csvToJSON(_ text: String) throws -> Data {
    let rows = TableOps.parse(text, separator: ",")
    guard let header = rows.first, !header.isEmpty else { throw DropError.wrongInput("The table is empty.") }
    let keys = uniqueKeys(header)
    let records = rows.dropFirst().filter { $0.contains { !$0.isEmpty } }.map { row in
      Dictionary(uniqueKeysWithValues: keys.enumerated().map { i, key in (key, i < row.count ? row[i] : "") })
    }
    return try JSONSerialization.data(
      withJSONObject: records, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }

  /// Blank or repeated headers get "column 3", "name 2" and so on.
  static func uniqueKeys(_ header: [String]) -> [String] {
    var used: Set<String> = []
    return header.enumerated().map { i, raw in
      var key = raw.trimmingCharacters(in: .whitespaces)
      if key.isEmpty { key = "column \(i + 1)" }
      var candidate = key
      var n = 2
      while used.contains(candidate) {
        candidate = "\(key) \(n)"
        n += 1
      }
      used.insert(candidate)
      return candidate
    }
  }

  /// RFC 4180 CSV: fields with commas, quotes or line breaks are quoted.
  static func csv(_ rows: [[String]]) -> String {
    rows.map { row in
      row.map { field in
        field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
          ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
      }.joined(separator: ",")
    }.joined(separator: "\r\n") + "\r\n"
  }

  // MARK: JSON ↔ plist, XML

  static func parseJSON(_ data: Data, name: String) throws -> Any {
    do {
      return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed, .json5Allowed])
    } catch {
      throw DropError.wrongInput("\(name) isn't valid JSON.")
    }
  }

  /// An XML property list. Plists have no null, so nulls are left out.
  static func jsonToPlist(_ data: Data, name: String) throws -> Data {
    guard let value = withoutNulls(try parseJSON(data, name: name)) else {
      throw DropError.wrongInput("\(name) holds only null.")
    }
    return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
  }

  private static func withoutNulls(_ value: Any) -> Any? {
    switch value {
    case is NSNull: nil
    case let object as [String: Any]: object.compactMapValues(withoutNulls)
    case let array as [Any]: array.compactMap(withoutNulls)
    default: value
    }
  }

  /// Any property list (XML or binary) as JSON: dates become ISO 8601 text and data
  /// becomes Base64.
  static func plistToJSON(_ data: Data, name: String) throws -> Data {
    guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
      throw DropError.wrongInput("\(name) isn't a property list.")
    }
    return try JSONSerialization.data(
      withJSONObject: jsonSafe(value),
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
  }

  private static func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let date as Date: ISO8601DateFormatter().string(from: date)
    case let data as Data: data.base64EncodedString()
    case let object as [String: Any]: object.mapValues(jsonSafe)
    case let array as [Any]: array.map(jsonSafe)
    default: value
    }
  }

  /// JSON as XML: objects become elements named by their keys, array items repeat their
  /// parent's name (or "item" at the top), and keys that aren't valid XML names are made so.
  static func jsonToXML(_ data: Data, name: String) throws -> String {
    let root = try parseJSON(data, name: name)
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    if let object = root as? [String: Any], object.count == 1, let key = object.keys.first,
      !(object[key] is [Any])
    {
      writeXML(object[key]!, name: xmlName(key), depth: 0, into: &out)
    } else {
      writeXML(root, name: "root", depth: 0, into: &out)
    }
    return out
  }

  private static func writeXML(_ value: Any, name: String, depth: Int, into out: inout String) {
    let pad = String(repeating: "  ", count: depth)
    switch value {
    case let object as [String: Any]:
      out += "\(pad)<\(name)>\n"
      for key in object.keys.sorted() {
        let child = xmlName(key)
        if let array = object[key] as? [Any] {
          for item in array { writeXML(item, name: child, depth: depth + 1, into: &out) }
        } else {
          writeXML(object[key]!, name: child, depth: depth + 1, into: &out)
        }
      }
      out += "\(pad)</\(name)>\n"
    case let array as [Any]:
      out += "\(pad)<\(name)>\n"
      for item in array { writeXML(item, name: "item", depth: depth + 1, into: &out) }
      out += "\(pad)</\(name)>\n"
    case is NSNull:
      out += "\(pad)<\(name)/>\n"
    default:
      out += "\(pad)<\(name)>\(escapeXML(scalarText(value)))</\(name)>\n"
    }
  }

  /// A valid XML element name: letters, digits, "-", "_" and "." only, not starting with a
  /// digit, "-", "." or "xml".
  static func xmlName(_ key: String) -> String {
    var name = String(
      key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_" })
    if name.isEmpty || name.first!.isNumber || name.first == "-" || name.first == "."
      || name.lowercased().hasPrefix("xml")
    {
      name = "_" + name
    }
    return name
  }

  static func escapeXML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  /// XML as JSON: an element with only text becomes a string; otherwise an object with
  /// "@attribute" keys, a key per child element (an array when it repeats), and "#text" for
  /// any text beside the children. A property list (XML or binary) is read as a plist.
  static func xmlToJSON(_ data: Data, name: String) throws -> Data {
    if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      String(decoding: data.prefix(512), as: UTF8.self).contains("<plist")
        || !data.starts(with: Array("<".utf8))
    {
      return try JSONSerialization.data(
        withJSONObject: jsonSafe(plist),
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }
    let builder = XMLTreeBuilder()
    let parser = XMLParser(data: data)
    parser.delegate = builder
    // Never fetch external entities or DTDs.
    parser.shouldResolveExternalEntities = false
    guard parser.parse(), let root = builder.root else {
      throw DropError.wrongInput("\(name) isn't well-formed XML.")
    }
    return try JSONSerialization.data(
      withJSONObject: [root.name: root.json], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }

  private final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
      self.name = name
      self.attributes = attributes
    }

    var json: Any {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if children.isEmpty && attributes.isEmpty { return trimmed }
      var object: [String: Any] = [:]
      for (k, v) in attributes { object["@\(k)"] = v }
      var order: [String] = []
      var grouped: [String: [Any]] = [:]
      for child in children {
        if grouped[child.name] == nil { order.append(child.name) }
        grouped[child.name, default: []].append(child.json)
      }
      for key in order { object[key] = grouped[key]!.count == 1 ? grouped[key]![0] : grouped[key]! }
      if !trimmed.isEmpty { object["#text"] = trimmed }
      return object
    }
  }

  private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
      attributes: [String: String]
    ) {
      let node = XMLNode(name: elementName, attributes: attributes)
      stack.last?.children.append(node)
      if root == nil { root = node }
      stack.append(node)
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
      stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
      stack.last?.text += String(decoding: block, as: UTF8.self)
    }
  }

  // MARK: vCard ↔ CSV

  /// The table columns, each with the CSV headers recognised for it (lower case).
  static let contactColumns: [(title: String, aliases: [String])] = [
    ("Name", ["name", "full name", "display name", "fn"]),
    ("Given Name", ["given name", "first name", "firstname", "given"]),
    ("Family Name", ["family name", "last name", "lastname", "surname", "family"]),
    ("Organization", ["organization", "organisation", "company", "org"]),
    ("Title", ["title", "job title"]),
    ("Email", ["email", "e-mail", "email address", "e-mail address", "mail"]),
    ("Phone", ["phone", "telephone", "tel", "mobile", "phone number", "mobile phone"]),
    ("Address", ["address", "street address", "home address"]),
    ("Birthday", ["birthday", "bday", "date of birth"]),
    ("URL", ["url", "website", "web page", "homepage"]),
    ("Note", ["note", "notes", "comment"]),
  ]

  /// One row per contact. Several emails or phones share a cell, separated by "; ".
  static func vCardToCSV(_ text: String, name: String) throws -> String {
    let cards = parseVCards(text)
    guard !cards.isEmpty else { throw DropError.wrongInput("\(name) has no contacts in it.") }
    let rows = cards.map { card -> [String] in
      func all(_ key: String) -> String { (card[key] ?? []).joined(separator: "; ") }
      let n = (card["N"]?.first ?? "").split(separator: ";", omittingEmptySubsequences: false).map(
        String.init)
      let adr = (card["ADR"]?.first ?? "").split(separator: ";", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
      let fn =
        card["FN"]?.first
        ?? [n.count > 1 ? n[1] : "", n.first ?? ""].filter { !$0.isEmpty }
        .joined(separator: " ")
      return [
        fn, n.count > 1 ? n[1] : "", n.first ?? "",
        (card["ORG"]?.first ?? "").replacingOccurrences(of: ";", with: ", "),
        all("TITLE"), all("EMAIL"), all("TEL"), adr, all("BDAY"), all("URL"), all("NOTE"),
      ]
    }
    return csv([contactColumns.map(\.title)] + rows)
  }

  /// Each card as property name → values (unescaped), after unfolding continuation lines.
  static func parseVCards(_ text: String) -> [[String: [String]]] {
    var lines: [String] = []
    for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .split(
        separator: "\n", omittingEmptySubsequences: false)
    {
      if raw.hasPrefix(" ") || raw.hasPrefix("\t"), !lines.isEmpty {
        lines[lines.count - 1] += raw.dropFirst()
      } else {
        lines.append(String(raw))
      }
    }
    var cards: [[String: [String]]] = []
    var current: [String: [String]]?
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let head = line[..<colon]
      // "item1.EMAIL;TYPE=work" → "EMAIL".
      let property =
        head.split(separator: ";").first.map { $0.split(separator: ".").last ?? $0 }?.uppercased() ?? ""
      let value = String(line[line.index(after: colon)...])
      switch property {
      case "BEGIN" where value.uppercased() == "VCARD": current = [:]
      case "END" where value.uppercased() == "VCARD":
        if let card = current, !card.isEmpty { cards.append(card) }
        current = nil
      default:
        guard current != nil else { continue }
        let isStructured = property == "N" || property == "ADR" || property == "ORG"
        current![property, default: []].append(unescapeVCard(value, keepSemicolons: isStructured))
      }
    }
    return cards
  }

  static func unescapeVCard(_ s: String, keepSemicolons: Bool) -> String {
    var out = ""
    var escaping = false
    for c in s {
      if escaping {
        switch c {
        case "n", "N": out += "\n"
        case ";" where keepSemicolons: out += "\u{1}"  // An escaped ";" inside a structured part.
        default: out.append(c)
        }
        escaping = false
      } else if c == "\\" {
        escaping = true
      } else {
        out.append(c)
      }
    }
    return keepSemicolons ? out.replacingOccurrences(of: "\u{1}", with: ",") : out
  }

  /// vCard 3.0 cards from a table whose headers name contact fields (see `contactColumns`).
  /// Several values in one cell, separated by ";", become several EMAIL or TEL lines.
  static func csvToVCard(_ text: String, name: String) throws -> String {
    let rows = TableOps.parse(text, separator: ",")
    guard let header = rows.first else { throw DropError.wrongInput("\(name) is empty.") }
    let lower = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    var index: [String: Int] = [:]
    for column in contactColumns {
      if let i = lower.firstIndex(where: column.aliases.contains) { index[column.title] = i }
    }
    guard
      index["Name"] != nil || index["Given Name"] != nil || index["Family Name"] != nil
        || index["Email"] != nil || index["Phone"] != nil
    else {
      throw DropError.wrongInput("\(name) has no Name, Email or Phone column to make contacts from.")
    }
    var out = ""
    for row in rows.dropFirst() {
      func cell(_ title: String) -> String {
        index[title].flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil } ?? ""
      }
      let given = cell("Given Name")
      let family = cell("Family Name")
      var full = cell("Name")
      if full.isEmpty { full = [given, family].filter { !$0.isEmpty }.joined(separator: " ") }
      if full.isEmpty { full = cell("Organization") }
      if full.isEmpty { full = cell("Email").split(separator: ";").first.map(String.init) ?? "" }
      guard !full.isEmpty else { continue }
      var card = ["BEGIN:VCARD", "VERSION:3.0", "FN:\(escapeVCard(full))"]
      card.append("N:\(escapeVCard(family));\(escapeVCard(given));;;")
      if !cell("Organization").isEmpty { card.append("ORG:\(escapeVCard(cell("Organization")))") }
      if !cell("Title").isEmpty { card.append("TITLE:\(escapeVCard(cell("Title")))") }
      for (title, property) in [("Email", "EMAIL;TYPE=INTERNET"), ("Phone", "TEL")] {
        for value in cell(title).split(separator: ";")
        where !value.trimmingCharacters(in: .whitespaces).isEmpty {
          card.append("\(property):\(escapeVCard(value.trimmingCharacters(in: .whitespaces)))")
        }
      }
      if !cell("Address").isEmpty { card.append("ADR:;;\(escapeVCard(cell("Address")));;;;") }
      if !cell("Birthday").isEmpty { card.append("BDAY:\(cell("Birthday"))") }
      if !cell("URL").isEmpty { card.append("URL:\(cell("URL"))") }
      if !cell("Note").isEmpty { card.append("NOTE:\(escapeVCard(cell("Note")))") }
      card.append("END:VCARD")
      out += card.map(fold).joined(separator: "\r\n") + "\r\n"
    }
    guard !out.isEmpty else { throw DropError.wrongInput("\(name) has no rows with a name, email or phone.") }
    return out
  }

  static func escapeVCard(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
      .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n")
  }

  /// Folds a line longer than 75 bytes into continuation lines, never splitting a character.
  static func fold(_ line: String) -> String {
    var parts: [String] = []
    var current = ""
    var bytes = 0
    for c in line {
      let size = String(c).utf8.count
      let limit = parts.isEmpty ? 75 : 74  // Continuations start with a space.
      if bytes + size > limit {
        parts.append(current)
        current = ""
        bytes = 0
      }
      current.append(c)
      bytes += size
    }
    parts.append(current)
    return parts.joined(separator: "\r\n ")
  }
}

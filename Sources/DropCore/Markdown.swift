import Foundation

/// A small Markdown-to-HTML converter covering what documents commonly use: ATX headings,
/// paragraphs, emphasis, inline code, fenced code, block quotes, nested lists, rules, pipe
/// tables, links, images and autolinks. Raw HTML in the source is escaped, not passed through.
public enum Markdown {
  public static func html(_ source: String) -> String {
    let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
    var parser = BlockParser(lines: lines)
    return parser.parse()
  }

  /// A full HTML page around `html(_:)`.
  public static func page(_ source: String, title: String) -> String {
    """
    <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(escape(title))</title></head>
    <body>\(html(source))</body></html>
    """
  }

  static func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }

  // MARK: Blocks

  private struct BlockParser {
    let lines: [String]
    var i = 0

    init(lines: [String]) { self.lines = lines }

    mutating func parse() -> String {
      var out: [String] = []
      var paragraph: [String] = []
      func flush() {
        if !paragraph.isEmpty {
          out.append("<p>\(Inline.render(paragraph.joined(separator: "\n")))</p>")
          paragraph = []
        }
      }
      while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
          flush()
          i += 1
        } else if let fence = Self.fence(trimmed) {
          flush()
          out.append(codeBlock(fence: fence, info: String(trimmed.dropFirst(fence.count))))
        } else if let (level, text) = Self.heading(trimmed) {
          flush()
          out.append("<h\(level)>\(Inline.render(text))</h\(level)>")
          i += 1
        } else if Self.isRule(trimmed) {
          flush()
          out.append("<hr>")
          i += 1
        } else if trimmed.hasPrefix(">") {
          flush()
          out.append(blockQuote())
        } else if Self.listMarker(line) != nil {
          flush()
          out.append(list())
        } else if trimmed.hasPrefix("|"), i + 1 < lines.count, Self.isTableDivider(lines[i + 1]) {
          flush()
          out.append(table())
        } else if !paragraph.isEmpty, Self.isSetextUnderline(trimmed) {
          let level = trimmed.hasPrefix("=") ? 1 : 2
          let text = paragraph.joined(separator: " ")
          paragraph = []
          out.append("<h\(level)>\(Inline.render(text))</h\(level)>")
          i += 1
        } else {
          paragraph.append(trimmed)
          i += 1
        }
      }
      flush()
      return out.joined(separator: "\n")
    }

    static func fence(_ s: String) -> String? {
      if s.hasPrefix("```") { return "```" }
      if s.hasPrefix("~~~") { return "~~~" }
      return nil
    }

    static func heading(_ s: String) -> (Int, String)? {
      let hashes = s.prefix { $0 == "#" }.count
      guard (1...6).contains(hashes) else { return nil }
      let rest = s.dropFirst(hashes)
      guard rest.isEmpty || rest.first == " " else { return nil }
      var text = rest.trimmingCharacters(in: .whitespaces)
      while text.hasSuffix("#") { text.removeLast() }
      return (hashes, text.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ s: String) -> Bool {
      let compact = s.replacingOccurrences(of: " ", with: "")
      guard compact.count >= 3, let c = compact.first, "-*_".contains(c) else { return false }
      return compact.allSatisfy { $0 == c }
    }

    static func isSetextUnderline(_ s: String) -> Bool {
      s.count >= 2 && (s.allSatisfy { $0 == "=" } || s.allSatisfy { $0 == "-" })
    }

    /// (indent, ordered, content) for a list item line.
    static func listMarker(_ line: String) -> (indent: Int, ordered: Bool, content: String)? {
      let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
      let s = line.trimmingCharacters(in: .whitespaces)
      if let c = s.first, "-*+".contains(c), s.dropFirst().first == " " {
        if isRule(s) { return nil }
        return (indent, false, String(s.dropFirst(2)))
      }
      let digits = s.prefix { $0.isNumber }
      if !digits.isEmpty, digits.count <= 9 {
        let rest = s.dropFirst(digits.count)
        if let c = rest.first, c == "." || c == ")", rest.dropFirst().first == " " {
          return (indent, true, String(rest.dropFirst(2)))
        }
      }
      return nil
    }

    static func isTableDivider(_ line: String) -> Bool {
      let s = line.trimmingCharacters(in: .whitespaces)
      guard s.contains("-"), s.contains("|") || s.contains("-") else { return false }
      return s.allSatisfy { "|-: ".contains($0) }
    }

    mutating func codeBlock(fence: String, info: String) -> String {
      i += 1
      var body: [String] = []
      while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
        body.append(lines[i])
        i += 1
      }
      i += 1  // closing fence
      let lang = info.trimmingCharacters(in: .whitespaces)
      let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
      return "<pre><code\(cls)>\(escape(body.joined(separator: "\n")))</code></pre>"
    }

    mutating func blockQuote() -> String {
      var inner: [String] = []
      while i < lines.count {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(">") else { break }
        var rest = t.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        inner.append(String(rest))
        i += 1
      }
      var nested = BlockParser(lines: inner)
      return "<blockquote>\(nested.parse())</blockquote>"
    }

    mutating func list() -> String {
      guard let first = Self.listMarker(lines[i]) else { return "" }
      let tag = first.ordered ? "ol" : "ul"
      var items: [String] = []
      while i < lines.count, let marker = Self.listMarker(lines[i]), marker.indent == first.indent,
        marker.ordered == first.ordered
      {
        var content = Inline.render(marker.content)
        i += 1
        // Continuation lines and nested lists.
        while i < lines.count {
          let line = lines[i]
          if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
          if let nested = Self.listMarker(line) {
            if nested.indent > first.indent {
              content += list()
              continue
            }
            break
          }
          content += " " + Inline.render(line.trimmingCharacters(in: .whitespaces))
          i += 1
        }
        items.append("<li>\(content)</li>")
        // A blank line between items keeps the list going.
        if i + 1 < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
          let next = Self.listMarker(lines[i + 1]), next.indent == first.indent, next.ordered == first.ordered
        {
          i += 1
        }
      }
      return "<\(tag)>\(items.joined())</\(tag)>"
    }

    mutating func table() -> String {
      func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
      }
      let header = cells(lines[i])
      i += 2
      var rows: [[String]] = []
      while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
        rows.append(cells(lines[i]))
        i += 1
      }
      let head = header.map { "<th>\(Inline.render($0))</th>" }.joined()
      let body = rows.map { row in
        "<tr>" + row.map { "<td>\(Inline.render($0))</td>" }.joined() + "</tr>"
      }.joined()
      return "<table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>"
    }
  }

  // MARK: Inline

  enum Inline {
    static func render(_ text: String) -> String {
      var out = ""
      let chars = Array(text)
      var i = 0
      func peek(_ s: String, at j: Int) -> Bool {
        let p = Array(s)
        guard j + p.count <= chars.count else { return false }
        return Array(chars[j..<j + p.count]) == p
      }
      func find(_ s: String, from j: Int) -> Int? {
        var k = j
        while k < chars.count {
          if peek(s, at: k) { return k }
          k += 1
        }
        return nil
      }
      while i < chars.count {
        let c = chars[i]
        if c == "\\", i + 1 < chars.count, "\\`*_{}[]()#+-.!|~<>".contains(chars[i + 1]) {
          out += escape(String(chars[i + 1]))
          i += 2
        } else if c == "`", let end = find("`", from: i + 1) {
          out += "<code>\(escape(String(chars[i + 1..<end])))</code>"
          i = end + 1
        } else if peek("**", at: i) || peek("__", at: i),
          let end = find(String(chars[i...i + 1]), from: i + 2),
          end > i + 2
        {
          out += "<strong>\(render(String(chars[i + 2..<end])))</strong>"
          i = end + 2
        } else if peek("~~", at: i), let end = find("~~", from: i + 2), end > i + 2 {
          out += "<del>\(render(String(chars[i + 2..<end])))</del>"
          i = end + 2
        } else if c == "*" || c == "_", i + 1 < chars.count, chars[i + 1] != " ",
          // Intraword underscores (snake_case) aren't emphasis.
          c == "*" || i == 0 || !chars[i - 1].isLetter,
          let end = find(String(c), from: i + 1), end > i + 1, chars[end - 1] != " "
        {
          out += "<em>\(render(String(chars[i + 1..<end])))</em>"
          i = end + 1
        } else if c == "!", i + 1 < chars.count, chars[i + 1] == "[", let link = linkAt(chars, i + 1) {
          out += "<img src=\"\(escape(link.url))\" alt=\"\(escape(link.text))\">"
          i = link.end
        } else if c == "[", let link = linkAt(chars, i) {
          out += "<a href=\"\(escape(link.url))\">\(render(link.text))</a>"
          i = link.end
        } else if c == "<", let end = find(">", from: i + 1),
          case let inner = String(chars[i + 1..<end]),
          inner.hasPrefix("http://") || inner.hasPrefix("https://") || inner.hasPrefix("mailto:")
        {
          out += "<a href=\"\(escape(inner))\">\(escape(inner))</a>"
          i = end + 1
        } else if c == "\n" {
          // Two trailing spaces mean a hard break.
          if out.hasSuffix("  ") {
            out.removeLast(2)
            out += "<br>"
          } else {
            out += " "
          }
          i += 1
        } else {
          out += escape(String(c))
          i += 1
        }
      }
      return out
    }

    /// `[text](url)` starting at `start` (the "[").
    static func linkAt(_ chars: [Character], _ start: Int) -> (text: String, url: String, end: Int)? {
      var depth = 0
      var j = start
      while j < chars.count {
        if chars[j] == "[" { depth += 1 }
        if chars[j] == "]" {
          depth -= 1
          if depth == 0 { break }
        }
        j += 1
      }
      guard j + 1 < chars.count, chars[j + 1] == "(", let close = chars[(j + 2)...].firstIndex(of: ")") else {
        return nil
      }
      var url = String(chars[j + 2..<close]).trimmingCharacters(in: .whitespaces)
      // Drop an optional "title".
      if let space = url.firstIndex(of: " ") { url = String(url[..<space]) }
      return (String(chars[start + 1..<j]), url, close + 1)
    }
  }
}

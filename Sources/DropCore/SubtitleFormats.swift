import Foundation

// ASS/SSA, SAMI and LRC reading and writing, plus decoding of legacy text encodings.
// SRT and WebVTT live in DocumentOps.swift.

extension SubtitleOps {
  // MARK: Reading

  /// Reads `url` as `format`'s cues.
  public static func read(_ url: URL) throws -> [SubtitleCue] {
    let text = try decode(Data(contentsOf: url), name: url.lastPathComponent)
    let format = SubtitleFormat(fileExtension: url.pathExtension) ?? .srt
    return parse(text, as: format)
  }

  public static func parse(_ text: String, as format: SubtitleFormat) -> [SubtitleCue] {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n"
    )
    .replacingOccurrences(of: "\u{FEFF}", with: "")
    switch format {
    case .srt, .vtt: return parse(normalized)
    case .ass, .ssa: return parseASS(normalized)
    case .smi: return parseSAMI(normalized)
    case .lrc: return parseLRC(normalized)
    }
  }

  /// Text from subtitle bytes: a BOM wins, then strict UTF-8, then the likeliest legacy
  /// encoding.
  public static func decode(_ data: Data, name: String = "The subtitle file") throws -> String {
    if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
    if data.starts(with: [0xFF, 0xFE]), let s = String(data: data, encoding: .utf16LittleEndian) {
      return s.replacingOccurrences(of: "\u{FEFF}", with: "")
    }
    if data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16BigEndian) {
      return s.replacingOccurrences(of: "\u{FEFF}", with: "")
    }
    if let s = String(data: data, encoding: .utf8) { return s }
    // Foundation scores each suggested encoding on the bytes and picks the likeliest.
    var converted: NSString?
    var lossy: ObjCBool = false
    let options: [StringEncodingDetectionOptionsKey: Any] = [
      .suggestedEncodingsKey: legacyEncodings.map(\.rawValue), .useOnlySuggestedEncodingsKey: true,
      .allowLossyKey: false,
    ]
    _ = NSString.stringEncoding(
      for: data, encodingOptions: options, convertedString: &converted, usedLossyConversion: &lossy)
    if let converted { return converted as String }
    throw DropError.readFailed(name)
  }

  /// The legacy encodings subtitle files come in: Korean (CP949), Japanese, Chinese
  /// (simplified and traditional), Cyrillic and Western.
  static let legacyEncodings: [String.Encoding] = [
    cfEncoding(.dosKorean), .shiftJIS, cfEncoding(.GB_18030_2000), cfEncoding(.big5_HKSCS_1999),
    .windowsCP1251, .windowsCP1252,
  ]

  private static func cfEncoding(_ e: CFStringEncodings) -> String.Encoding {
    String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(e.rawValue)))
  }

  /// `[Events]` lines: `Format:` names the fields, and each `Dialogue:` fills them, with the
  /// text last (it may contain commas).
  static func parseASS(_ text: String) -> [SubtitleCue] {
    var fields = [
      "layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text",
    ]
    var inEvents = false
    var cues: [SubtitleCue] = []
    for raw in text.split(separator: "\n") {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("[") {
        inEvents = line.lowercased() == "[events]"
        continue
      }
      guard inEvents, let colon = line.firstIndex(of: ":") else { continue }
      let key = line[..<colon].lowercased()
      let value = line[line.index(after: colon)...]
      if key == "format" {
        fields = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        continue
      }
      guard key == "dialogue" else { continue }
      let values = value.split(
        separator: ",", maxSplits: max(fields.count - 1, 0), omittingEmptySubsequences: false
      )
      .map { String($0) }
      func field(_ name: String) -> String? {
        fields.firstIndex(of: name).flatMap { $0 < values.count ? values[$0] : nil }
      }
      guard let start = field("start").flatMap(time), let end = field("end").flatMap(time), end > start,
        let body = field("text").map(assTextToTags), !body.isEmpty
      else { continue }
      cues.append(SubtitleCue(start: start, end: end, text: body))
    }
    return cues.sorted { $0.start < $1.start }
  }

  /// ASS text to SRT-style text: `\N` breaks lines; bold and italic overrides become tags;
  /// other overrides (`{\pos(…)}`, colours, karaoke) are dropped.
  static func assTextToTags(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\h", with: " ")
    let map = [("\\i1", "<i>"), ("\\i0", "</i>"), ("\\b1", "<b>"), ("\\b0", "</b>")]
    out = replace(#"\{([^}]*)\}"#, in: out) { block in
      map.compactMap { block.contains($0.0) ? $0.1 : nil }.joined()
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// `<SYNC Start=ms>` blocks: each shows its text until the next one. A block holding only
  /// `&nbsp;` clears the screen. With several language classes, the first is kept.
  static func parseSAMI(_ text: String) -> [SubtitleCue] {
    guard
      let sync = try? NSRegularExpression(
        pattern: #"<sync\b[^>]*\bstart\s*=\s*["']?(\d+)[^>]*>"#, options: .caseInsensitive)
    else { return [] }
    let ns = text as NSString
    let matches = sync.matches(in: text, range: NSRange(location: 0, length: ns.length))
    var firstClass: String?
    var blocks: [(start: Double, text: String)] = []
    for (i, m) in matches.enumerated() {
      let bodyStart = m.range.location + m.range.length
      let bodyEnd = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
      var body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
      if let end = body.range(of: "</body", options: .caseInsensitive) {
        body = String(body[..<end.lowerBound])
      }
      let paragraphs = samiParagraphs(body)
      if firstClass == nil { firstClass = paragraphs.first { !$0.text.isEmpty }?.cls }
      let chosen = paragraphs.first { $0.cls == firstClass } ?? paragraphs.first
      let ms = Double(ns.substring(with: m.range(at: 1))) ?? 0
      blocks.append((ms / 1000, chosen.map { samiText($0.text) } ?? ""))
    }
    var cues: [SubtitleCue] = []
    for (i, block) in blocks.enumerated() where !block.text.isEmpty {
      let end = i + 1 < blocks.count ? blocks[i + 1].start : block.start + 4
      if end > block.start { cues.append(SubtitleCue(start: block.start, end: end, text: block.text)) }
    }
    return cues
  }

  /// A SYNC block's `<P Class=…>` paragraphs; text without a `<P>` counts as one.
  private static func samiParagraphs(_ body: String) -> [(cls: String, text: String)] {
    guard let p = try? NSRegularExpression(pattern: #"<p\b([^>]*)>"#, options: .caseInsensitive) else {
      return []
    }
    let ns = body as NSString
    let matches = p.matches(in: body, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return [("", body)] }
    return matches.enumerated().map { i, m in
      let attrs = ns.substring(with: m.range(at: 1))
      let cls = firstMatch(#"class\s*=\s*["']?([\w-]+)"#, in: attrs)?.lowercased() ?? ""
      let start = m.range.location + m.range.length
      let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
      return (cls, ns.substring(with: NSRange(location: start, length: end - start)))
    }
  }

  /// SAMI's HTML to plain text with `<i>`/`<b>` kept and `<br>` as a line break.
  private static func samiText(_ html: String) -> String {
    var s = html.replacingOccurrences(of: "\n", with: "")
    s = replace(#"<br\s*/?>"#, in: s) { _ in "\n" }
    s = replace(#"<(/?)([a-zA-Z]+)[^>]*>"#, in: s) { tag in
      let lower = tag.lowercased()
      for t in ["i", "b", "u"] where lower == "<\(t)>" || lower == "</\(t)>" || lower.hasPrefix("<\(t) ") {
        return lower.hasPrefix("</") ? "</\(t)>" : "<\(t)>"
      }
      return ""
    }
    s = decodeEntities(s)
    return s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  /// `[mm:ss.xx]` lines (several stamps may share one line). `[offset:±ms]` shifts every
  /// stamp; word-timing `<mm:ss.xx>` marks and `[ar:…]`-style tags are dropped. Each line
  /// lasts until the next one; the last for four seconds.
  static func parseLRC(_ text: String) -> [SubtitleCue] {
    var offset = 0.0
    var lines: [(start: Double, text: String)] = []
    for raw in text.split(separator: "\n") {
      var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
      var stamps: [Double] = []
      while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
        let tag = rest[rest.index(after: rest.startIndex)..<close]
        if tag.lowercased().hasPrefix("offset:"),
          let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces))
        {
          // A positive offset shows lyrics sooner.
          offset = -ms / 1000
        } else if let t = time(String(tag)) {
          stamps.append(t)
        }
        rest = rest[rest.index(after: close)...]
      }
      let words = replace(#"<\d+:\d+(\.\d+)?>"#, in: String(rest)) { _ in "" }
        .trimmingCharacters(in: .whitespaces)
      for t in stamps { lines.append((t, words)) }
    }
    lines.sort { $0.start < $1.start }
    var cues: [SubtitleCue] = []
    for (i, line) in lines.enumerated() where !line.text.isEmpty {
      let start = max(line.start + offset, 0)
      let end = i + 1 < lines.count ? max(lines[i + 1].start + offset, 0) : start + 4
      if end > start { cues.append(SubtitleCue(start: start, end: end, text: line.text)) }
    }
    return cues
  }

  // MARK: Writing

  /// Advanced SubStation Alpha (v4+) with one default style.
  static func writeASS(_ cues: [SubtitleCue]) -> String {
    var s = "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nWrapStyle: 0\n\n"
    s += "[V4+ Styles]\n"
    s += "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
    s += "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, "
    s += "Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    s += "Style: Default,Helvetica,64,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,"
    s += "0,0,0,0,100,100,0,0,1,3,1,2,60,60,50,1\n\n"
    s += "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    for c in cues {
      s += "Dialogue: 0,\(assStamp(c.start)),\(assStamp(c.end)),Default,,0,0,0,,\(tagsToASS(c.text))\n"
    }
    return s
  }

  /// SubStation Alpha v4 (the older SSA) with one default style.
  static func writeSSA(_ cues: [SubtitleCue]) -> String {
    var s = "[Script Info]\nScriptType: v4.00\nPlayResX: 1920\nPlayResY: 1080\n\n"
    s += "[V4 Styles]\n"
    s += "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, "
    s +=
      "Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding\n"
    s += "Style: Default,Helvetica,64,16777215,255,0,0,0,0,1,3,1,2,60,60,50,0,1\n\n"
    s += "[Events]\nFormat: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    for c in cues {
      s += "Dialogue: Marked=0,\(assStamp(c.start)),\(assStamp(c.end)),Default,,0,0,0,,\(tagsToASS(c.text))\n"
    }
    return s
  }

  /// "h:mm:ss.cc", the (centisecond) time format of ASS and SSA.
  static func assStamp(_ t: Double) -> String {
    let cs = Int((max(t, 0) * 100).rounded())
    return String(format: "%d:%02d:%02d.%02d", cs / 360_000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
  }

  /// SRT/VTT text to ASS: bold and italic become overrides, other tags go, lines join with `\N`.
  static func tagsToASS(_ s: String) -> String {
    let map = ["<i>": "{\\i1}", "</i>": "{\\i0}", "<b>": "{\\b1}", "</b>": "{\\b0}"]
    let tagged = replace(#"</?[a-zA-Z][^>]*>"#, in: stripVTTTags(s)) { map[$0.lowercased()] ?? "" }
    return tagged.replacingOccurrences(of: "\n", with: "\\N")
  }

  /// SAMI with one English caption class. Each cue gets a SYNC, and a blank SYNC clears it
  /// unless the next cue starts right away.
  static func writeSAMI(_ cues: [SubtitleCue]) -> String {
    var s = "<SAMI>\n<HEAD>\n<TITLE>Subtitles</TITLE>\n<STYLE TYPE=\"text/css\">\n<!--\n"
    s += "P { margin-left: 8pt; margin-right: 8pt; text-align: center; font-family: sans-serif; }\n"
    s += ".ENCC { Name: English; lang: en-US; }\n-->\n</STYLE>\n</HEAD>\n<BODY>\n"
    for (i, c) in cues.enumerated() {
      let text = escapeHTML(stripVTTTags(c.text)).replacingOccurrences(of: "\n", with: "<br>")
      s += "<SYNC Start=\(ms(c.start))><P Class=ENCC>\(text)\n"
      if i + 1 == cues.count || cues[i + 1].start > c.end + 0.0005 {
        s += "<SYNC Start=\(ms(c.end))><P Class=ENCC>&nbsp;\n"
      }
    }
    return s + "</BODY>\n</SAMI>\n"
  }

  /// LRC: one `[mm:ss.xx]` line per cue (line breaks become " / "), plus an empty stamp
  /// where a gap follows, so the lyric doesn't linger.
  static func writeLRC(_ cues: [SubtitleCue]) -> String {
    var s = ""
    for (i, c) in cues.enumerated() {
      let text = replace(#"</?[a-zA-Z][^>]*>"#, in: c.text) { _ in "" }
        .split(separator: "\n").joined(separator: " / ")
      s += "[\(lrcStamp(c.start))]\(text)\n"
      if i + 1 == cues.count || cues[i + 1].start > c.end + 0.005 {
        s += "[\(lrcStamp(c.end))]\n"
      }
    }
    return s
  }

  /// "mm:ss.xx" (minutes may pass 99).
  static func lrcStamp(_ t: Double) -> String {
    let cs = Int((max(t, 0) * 100).rounded())
    return String(format: "%02d:%02d.%02d", cs / 6000, cs / 100 % 60, cs % 100)
  }

  // MARK: Helpers

  private static func ms(_ t: Double) -> Int { Int((max(t, 0) * 1000).rounded()) }

  static func escapeHTML(_ s: String) -> String {
    // Keep the <i>, <b> and <u> tags SRT allows; escape everything else.
    let escaped = s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
    return replace(#"&lt;(/?[ibu])&gt;"#, in: escaped) { m in
      m.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
  }

  static func decodeEntities(_ s: String) -> String {
    let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'"]
    var out = s
    for (k, v) in named { out = out.replacingOccurrences(of: k, with: v, options: .caseInsensitive) }
    out = replace(#"&#(x?)([0-9a-fA-F]+);"#, in: out) { m in
      let hex = m.dropFirst(2).hasPrefix("x") || m.dropFirst(2).hasPrefix("X")
      let digits = m.dropFirst(hex ? 3 : 2).dropLast()
      return UInt32(digits, radix: hex ? 16 : 10).flatMap(Unicode.Scalar.init).map { String($0) } ?? m
    }
    return out.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
  }

  /// Replaces each match of `pattern` with `transform(match)`.
  static func replace(_ pattern: String, in s: String, _ transform: (String) -> String) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return s }
    let ns = s as NSString
    var out = ""
    var last = 0
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
      out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
      out += transform(ns.substring(with: m.range))
      last = m.range.location + m.range.length
    }
    return out + ns.substring(from: last)
  }

  private static func firstMatch(_ pattern: String, in s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
      let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
      let r = Range(m.range(at: 1), in: s)
    else { return nil }
    return String(s[r])
  }
}

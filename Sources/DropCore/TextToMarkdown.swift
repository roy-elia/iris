import Foundation

/// Turns text that never lived in a file (pasted, or dragged out of an app) into a Markdown
/// file, ready to attach to an AI chat. The text is kept exactly as copied, apart from
/// normalised line endings and one trailing newline.
public enum TextToMarkdown {
  public enum Failure: Error, Equatable, Sendable {
    case empty
  }

  /// The longest slug taken from the first line of the text.
  static let maxNameLength = 48

  /// The file contents for `text`: `\n` line endings, no BOM, one trailing newline.
  public static func contents(of text: String) -> String {
    var body = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
    while body.last?.isWhitespace == true { body.removeLast() }
    return body + "\n"
  }

  /// A file name (without extension) taken from the first line of text, such as the heading of
  /// a chat export, or "Pasted text <date time>" when that line gives nothing usable.
  public static func baseName(for text: String, date: Date = Date()) -> String {
    let firstLine =
      text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty } ?? ""
    // Drop Markdown heading/list/quote markers, then anything a file name can't hold.
    let stripped = firstLine.drop { "#>-*+ \t".contains($0) }
    let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
    var name =
      String(stripped).unicodeScalars
      .map { illegal.contains($0) ? " " : String($0) }.joined()
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if name.count > maxNameLength {
      name = String(name.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }
    while name.hasPrefix(".") { name.removeFirst() }
    if name.isEmpty {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
      return "Pasted text \(formatter.string(from: date))"
    }
    return name
  }

  /// Writes `text` to a new `.md` file in `directory`, never overwriting an existing file.
  @discardableResult
  public static func write(
    _ text: String, to directory: URL, date: Date = Date(), fileManager: FileManager = .default
  ) throws -> URL {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
    let desired = directory.appendingPathComponent(baseName(for: text, date: date) + ".md")
    let url = OutputNamer.uniqueURL(for: desired, fileManager: fileManager)
    try Data(contents(of: text).utf8).write(to: url, options: .withoutOverwriting)
    return url
  }

  /// Where text with no source file is saved: the chosen output folder, otherwise Downloads.
  public static func destination(for location: OutputLocation, fileManager: FileManager = .default) -> URL {
    switch location {
    case .folder(let url): url
    case .nextToSource: OutputNamer.downloadsDirectory(fileManager)
    }
  }
}

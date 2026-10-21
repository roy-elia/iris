import Foundation

/// Splits a wheel's segments into pages of at most `perPage`, so every wheel stays small
/// enough for a full label and symbol in each petal. The first page holds the segments people
/// reach for most; the rest follow on later pages, in their original order. Pressing the
/// wheel's modifier again turns the page.
enum WheelPaging {
  static let perPage = 8

  /// Segment titles by how often they're needed, most common first. A title not listed
  /// ranks last, and ties keep the wheel's own order.
  private static let priority: [String] = [
    // Image and video formats
    "png", "pdf", "jpeg", "heic", "webp", "gif", "tiff", "avif", "mp4", "hevc", "720p", "mov", "webm",
    // Audio formats
    "mp3", "m4a", "wav", "aac", "flac", "ogg", "opus",
    // Document formats
    "docx", "rtf", "txt", "markdown", "html", "epub",
    // Tools
    "compress", "trim", "split", "join", "speed", "crop", "subtitles", "metadata", "resize", "annotate",
    "redact", "add bg", "adjust",
  ]
  private static let rank: [String: Int] = Dictionary(
    uniqueKeysWithValues: priority.enumerated().map { ($1, $0) })

  static func pages(_ items: [WheelItem]) -> [[WheelItem]] {
    guard items.count > perPage else { return [items] }
    let ranked = items.indices.sorted {
      let a = rank[items[$0].title.lowercased()] ?? Int.max
      let b = rank[items[$1].title.lowercased()] ?? Int.max
      return a == b ? $0 < $1 : a < b
    }
    let first = Set(ranked.prefix(perPage))
    var pages = [items.indices.filter(first.contains).map { items[$0] }]
    let rest = items.indices.filter { !first.contains($0) }.map { items[$0] }
    var start = 0
    while start < rest.count {
      pages.append(Array(rest[start..<min(start + perPage, rest.count)]))
      start += perPage
    }
    return pages
  }
}

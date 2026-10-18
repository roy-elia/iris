import Foundation

/// Saves and loads `Settings` as JSON.
public struct SettingsStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// Returns saved settings, or defaults if the file is missing or unreadable.
  public func load() -> Settings {
    guard let data = try? Data(contentsOf: fileURL),
      let settings = try? JSONDecoder().decode(Settings.self, from: data)
    else { return Settings() }
    return settings
  }

  public func save(_ settings: Settings) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(settings).write(to: fileURL, options: .atomic)
  }
}

/// Keeps the most recent operations, newest first, persisted as JSON.
public struct HistoryStore: Sendable {
  public static let defaultLimit = 50

  public let fileURL: URL
  public let limit: Int

  public init(fileURL: URL, limit: Int = HistoryStore.defaultLimit) {
    self.fileURL = fileURL
    self.limit = max(1, limit)
  }

  public func load() -> [HistoryEntry] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
  }

  /// Adds `entry` at the front, trims to `limit`, saves, and returns the new list.
  @discardableResult
  public func append(_ entry: HistoryEntry) throws -> [HistoryEntry] {
    let entries = Array(([entry] + load()).prefix(limit))
    try write(entries)
    return entries
  }

  public func clear() throws {
    try write([])
  }

  private func write(_ entries: [HistoryEntry]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted]
    try encoder.encode(entries).write(to: fileURL, options: .atomic)
  }
}

extension URL {
  /// `~/Library/Application Support/FileDropUtility`.
  public static var appSupportFolder: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("FileDropUtility", isDirectory: true)
  }
}

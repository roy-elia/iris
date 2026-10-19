import CoreGraphics
import Foundation

// MARK: - Wheel themes

/// How the drag wheels look.
public enum WheelTheme: String, CaseIterable, Codable, Sendable {
  /// Regular Liquid Glass (the default). The raw values predate the glass names and are kept
  /// so saved settings still load.
  case dark
  /// Clear Liquid Glass, which shows more of what's behind it.
  case light
  /// Liquid Glass tinted with the accent colour.
  case tinted

  public var title: String {
    switch self {
    case .dark: "Regular"
    case .light: "Clear"
    case .tinted: "Tinted"
    }
  }
}

// MARK: - Float stacks

public enum FloatEdge: String, Codable, Sendable {
  case left, right
}

/// A Float: a stack of files kept in a glass tab docked to a screen edge. Closing a Float
/// never touches the files.
public struct FloatStack: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public private(set) var urls: [URL]
  public var edge: FloatEdge
  /// Where the tab sits along the edge: 0 at the bottom of the visible frame, 1 at the top.
  public var position: Double

  public static let maxFiles = 200

  public init(id: UUID = UUID(), urls: [URL], edge: FloatEdge = .right, position: Double = 0.6) {
    self.id = id
    self.urls = []
    self.edge = edge
    self.position = min(max(position, 0), 1)
    add(urls)
  }

  /// Adds files that aren't already in the stack, newest on top. Returns how many were added.
  @discardableResult
  public mutating func add(_ new: [URL]) -> Int {
    let existing = Set(urls.map(\.standardizedFileURL))
    let fresh = new.map(\.standardizedFileURL).reduce(into: [URL]()) { list, url in
      if !existing.contains(url) && !list.contains(url) { list.append(url) }
    }
    urls = Array((fresh.reversed() + urls).prefix(Self.maxFiles))
    return fresh.count
  }

  public mutating func remove(_ url: URL) {
    urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
  }

  /// Drops files that have been moved or deleted since they were added.
  public mutating func pruneMissing(fileManager: FileManager = .default) {
    urls.removeAll { !fileManager.fileExists(atPath: $0.path) }
  }

  public var isEmpty: Bool { urls.isEmpty }
}

/// Where Float tabs go on screen. All rects are in AppKit screen coordinates (y up).
public enum FloatPlacement {
  /// How much of a collapsed tab hides past the screen edge.
  public static let tuck: CGFloat = 18

  /// The edge and position a tab dropped with its centre at `point` snaps to.
  public static func snap(_ point: CGPoint, in visible: CGRect) -> (edge: FloatEdge, position: Double) {
    let edge: FloatEdge = point.x < visible.midX ? .left : .right
    let position = visible.height > 0 ? Double((point.y - visible.minY) / visible.height) : 0.5
    return (edge, min(max(position, 0), 1))
  }

  /// The window frame for a tab of `size`. Collapsed tabs tuck partly off screen; expanded
  /// ones sit fully inside it. The frame is kept within the visible area vertically.
  public static func frame(
    size: CGSize, edge: FloatEdge, position: Double, in visible: CGRect, expanded: Bool
  ) -> CGRect {
    let inset: CGFloat = expanded ? 8 : -tuck
    let x = edge == .left ? visible.minX + inset : visible.maxX - size.width - inset
    let centreY = visible.minY + CGFloat(position) * visible.height
    let y = min(max(centreY - size.height / 2, visible.minY + 8), visible.maxY - size.height - 8)
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }
}

/// Saves open Floats so they come back after a relaunch.
public struct FloatStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() -> [FloatStack] {
    guard let data = try? Data(contentsOf: fileURL),
      var stacks = try? JSONDecoder().decode([FloatStack].self, from: data)
    else { return [] }
    for i in stacks.indices { stacks[i].pruneMissing() }
    return stacks.filter { !$0.isEmpty }
  }

  public func save(_ stacks: [FloatStack]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(stacks).write(to: fileURL, options: .atomic)
  }
}

// MARK: - Update check

/// A newer release, from a GitHub-style releases feed.
public struct AvailableUpdate: Equatable, Sendable {
  public let version: String
  public let pageURL: URL
  public let notes: String
}

/// Checks a releases feed (the JSON GitHub serves at `/repos/<owner>/<repo>/releases/latest`).
/// The feed URL comes from the app's Info.plist (`FDUUpdateFeedURL`) and must be HTTPS. Nothing
/// is checked unless the user turns the check on in Settings.
public enum UpdateChecker {
  public static let feedKey = "FDUUpdateFeedURL"
  public static let interval: TimeInterval = 24 * 60 * 60

  public static func feedURL(bundle: Bundle = .main) -> URL? {
    guard let s = bundle.object(forInfoDictionaryKey: feedKey) as? String, let url = URL(string: s),
      url.scheme == "https"
    else { return nil }
    return url
  }

  public static func currentVersion(bundle: Bundle = .main) -> String {
    bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  /// The release in `data` if it's newer than `current`. Drafts and pre-releases are ignored.
  public static func parse(_ data: Data, current: String) throws -> AvailableUpdate? {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tag = json["tag_name"] as? String
    else { throw DropError.wrongInput("The update feed didn't return a release.") }
    if json["draft"] as? Bool == true || json["prerelease"] as? Bool == true { return nil }
    guard isNewer(tag, than: current) else { return nil }
    guard let page = (json["html_url"] as? String).flatMap(URL.init(string:)), page.scheme == "https" else {
      throw DropError.wrongInput("The update feed's release page isn't a secure link.")
    }
    let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    return AvailableUpdate(version: version, pageURL: page, notes: json["body"] as? String ?? "")
  }

  /// Compares dotted versions numerically ("1.10" > "1.9"; "v2.0" == "2").
  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
      let trimmed = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
      return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
    let a = parts(candidate)
    let b = parts(current)
    for i in 0..<max(a.count, b.count) {
      let x = i < a.count ? a[i] : 0
      let y = i < b.count ? b[i] : 0
      if x != y { return x > y }
    }
    return false
  }

  /// Fetches the feed and returns a newer release, if there is one.
  public static func check(feed: URL, current: String, session: URLSession = .shared) async throws
    -> AvailableUpdate?
  {
    var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw DropError.wrongInput("The update feed couldn't be reached.")
    }
    return try parse(data, current: current)
  }
}

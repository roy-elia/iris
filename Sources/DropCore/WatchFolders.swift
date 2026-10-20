import Foundation

/// A folder whose new files are processed automatically with a recipe.
public struct WatchFolder: Codable, Equatable, Identifiable, Sendable {
  public enum Afterwards: String, Codable, CaseIterable, Sendable {
    /// Leave the original where it is.
    case keep
    /// Move the original into an "Originals" folder inside the watched folder.
    case moveToOriginals

    public var title: String {
      switch self {
      case .keep: "Leave originals"
      case .moveToOriginals: "Move originals to \"Originals\""
      }
    }
  }

  public var id: UUID
  public var path: String
  public var recipe: Recipe
  public var afterwards: Afterwards
  public var enabled: Bool

  /// Results go here, inside the watched folder, so they aren't picked up again.
  public static let outputFolderName = "Converted"
  public static let originalsFolderName = "Originals"

  public init(
    id: UUID = UUID(), path: String, recipe: Recipe, afterwards: Afterwards = .keep, enabled: Bool = true
  ) {
    self.id = id
    self.path = path
    self.recipe = recipe
    self.afterwards = afterwards
    self.enabled = enabled
  }

  public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
  public var outputURL: URL { url.appendingPathComponent(Self.outputFolderName, isDirectory: true) }
  public var originalsURL: URL { url.appendingPathComponent(Self.originalsFolderName, isDirectory: true) }
  public var name: String { url.lastPathComponent }

  /// Ready-made recipes offered for watch folders, next to the saved ones.
  public static let presets: [Recipe] = [
    Recipe(id: preset(1), name: "Subtitles (SRT)", steps: [.action(.transcribe)]),
    Recipe(id: preset(2), name: "Summaries", steps: [.action(.summarize)]),
    Recipe(id: preset(3), name: "Name from content", steps: [.action(.renameByContent)]),
    Recipe(id: preset(4), name: "Images to JPEG", steps: [.action(.convertImage(.jpeg))]),
    Recipe(id: preset(5), name: "Compress", steps: [.action(.compress)]),
  ]

  private static func preset(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
  }
}

/// Watches folders and runs each one's recipe on files that appear in it (not in subfolders).
/// A file is processed once its size has stopped changing, so copies and downloads in
/// progress are left alone. Files already there when watching starts are skipped.
public final class FolderWatcher: @unchecked Sendable {
  public typealias Report = @Sendable (WatchFolder, URL, OperationResult) -> Void

  /// How often folders are checked (directory change events also trigger a check).
  public var pollInterval: TimeInterval = 2
  /// A file must keep the same size for this long before it's processed.
  public var settleTime: TimeInterval = 1.5

  private let lock = NSLock()
  private var folders: [WatchFolder] = []
  private var seen: [UUID: Set<String>] = [:]
  private var pending: [UUID: [String: (size: Int64, since: Date)]] = [:]
  private var sources: [UUID: DispatchSourceFileSystemObject] = [:]
  private var timer: DispatchSourceTimer?
  private var running: Set<String> = []
  private let queue = DispatchQueue(label: "FolderWatcher")
  private let settings: @Sendable () -> AppSettings
  private let report: Report

  public init(settings: @escaping @Sendable () -> AppSettings, report: @escaping Report) {
    self.settings = settings
    self.report = report
  }

  deinit { stop() }

  /// Starts (or updates) watching. Folders removed from the list stop being watched.
  public func update(_ list: [WatchFolder]) {
    lock.withLock {
      let active = list.filter { $0.enabled && FileManager.default.fileExists(atPath: $0.path) }
      let ids = Set(active.map(\.id))
      for (id, source) in sources where !ids.contains(id) {
        source.cancel()
        sources[id] = nil
        seen[id] = nil
        pending[id] = nil
      }
      for folder in active where sources[folder.id] == nil || seen[folder.id] == nil {
        seen[folder.id] = Set(Self.candidates(in: folder).map(\.lastPathComponent))
        pending[folder.id] = [:]
        sources[folder.id] = makeSource(for: folder)
      }
      folders = active
      if timer == nil, !active.isEmpty {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
      } else if active.isEmpty {
        timer?.cancel()
        timer = nil
      }
    }
  }

  public func stop() {
    lock.withLock {
      for source in sources.values { source.cancel() }
      sources = [:]
      timer?.cancel()
      timer = nil
      folders = []
    }
  }

  private func makeSource(for folder: WatchFolder) -> DispatchSourceFileSystemObject? {
    let fd = open(folder.path, O_EVTONLY)
    guard fd >= 0 else { return nil }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
    source.setEventHandler { [weak self] in self?.scan() }
    source.setCancelHandler { close(fd) }
    source.resume()
    return source
  }

  /// Regular, visible files directly in the folder that aren't partial downloads.
  static func candidates(in folder: WatchFolder, fileManager: FileManager = .default) -> [URL] {
    let items =
      (try? fileManager.contentsOfDirectory(
        at: folder.url, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
        options: [.skipsHiddenFiles])) ?? []
    let partial: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]
    return items.filter { url in
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey])
      let isFile = values?.isRegularFile == true || values?.isPackage == true
      return isFile && !partial.contains(url.pathExtension.lowercased())
    }
  }

  /// Notes new files, and starts the ones whose size has settled.
  func scan(now: Date = Date()) {
    let ready: [(WatchFolder, URL)] = lock.withLock {
      var ready: [(WatchFolder, URL)] = []
      for folder in folders {
        var seenNames = seen[folder.id] ?? []
        var waiting = pending[folder.id] ?? [:]
        for url in Self.candidates(in: folder) where !seenNames.contains(url.lastPathComponent) {
          let name = url.lastPathComponent
          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
          if let entry = waiting[name], entry.size == size {
            if now.timeIntervalSince(entry.since) >= settleTime {
              waiting[name] = nil
              seenNames.insert(name)
              ready.append((folder, url))
            }
          } else {
            waiting[name] = (size, now)
          }
        }
        seen[folder.id] = seenNames
        pending[folder.id] = waiting
      }
      return ready
    }
    for (folder, url) in ready { process(url, in: folder) }
  }

  private func process(_ url: URL, in folder: WatchFolder) {
    let key = url.path
    guard lock.withLock({ running.insert(key).inserted }) else { return }
    var settings = settings()
    settings.outputLocation = .folder(folder.outputURL)
    let report = report
    Task {
      try? FileManager.default.createDirectory(at: folder.outputURL, withIntermediateDirectories: true)
      var result = await RecipeRunner.run(folder.recipe, on: [url], settings: settings)
      if result.failures.isEmpty, folder.afterwards == .moveToOriginals,
        FileManager.default.fileExists(atPath: url.path)
      {
        do {
          try FileManager.default.createDirectory(at: folder.originalsURL, withIntermediateDirectories: true)
          let target = OutputNamer.uniqueURL(
            for: folder.originalsURL.appendingPathComponent(url.lastPathComponent))
          try FileManager.default.moveItem(at: url, to: target)
        } catch {
          result.failures.append(
            .init(
              file: url.lastPathComponent,
              message: "Couldn't move the original: \(error.localizedDescription)"))
        }
      }
      self.lock.withLock { _ = self.running.remove(key) }
      report(folder, url, result)
    }
  }
}

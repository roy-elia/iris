import Foundation

/// Picks output paths that never overwrite an existing file.
public enum OutputNamer {
  /// Returns `desired` if nothing exists there, otherwise `name (1).ext`, `name (2).ext`, ...
  /// `reserved` holds paths already claimed in this run but not yet written.
  public static func uniqueURL(
    for desired: URL, reserved: Set<URL> = [], fileManager: FileManager = .default
  ) -> URL {
    func taken(_ url: URL) -> Bool {
      fileManager.fileExists(atPath: url.path) || reserved.contains(url.standardizedFileURL)
    }
    guard taken(desired) else { return desired }

    let directory = desired.deletingLastPathComponent()
    let ext = desired.pathExtension
    let base = desired.deletingPathExtension().lastPathComponent
    var n = 1
    while true {
      let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
      let candidate = directory.appendingPathComponent(name)
      if !taken(candidate) { return candidate }
      n += 1
    }
  }

  /// The folder an output for `source` goes in.
  public static func directory(
    for source: URL, location: OutputLocation, fileManager: FileManager = .default
  ) -> URL {
    resolve(for: source, location: location, fileManager: fileManager).url
  }

  /// The folder an output for `source` goes in, and whether Downloads stood in for the chosen
  /// one: the original's folder when it is read-only or an app's private cache (attachments
  /// dragged out of Mail or Messages live there), or a chosen folder that can't be written.
  public static func resolve(
    for source: URL, location: OutputLocation, fileManager: FileManager = .default,
    downloads: URL? = nil
  ) -> (url: URL, fellBack: Bool) {
    let chosen: URL
    switch location {
    case .nextToSource:
      chosen = source.deletingLastPathComponent()
      if isHiddenAppStorage(chosen, home: fileManager.homeDirectoryForCurrentUser) {
        return (downloads ?? downloadsDirectory(fileManager), true)
      }
    case .folder(let url):
      chosen = url
    }
    // A folder that doesn't exist yet is created later; only an existing read-only one falls back.
    if fileManager.fileExists(atPath: chosen.path), !fileManager.isWritableFile(atPath: chosen.path) {
      return (downloads ?? downloadsDirectory(fileManager), true)
    }
    return (chosen, false)
  }

  public static func downloadsDirectory(_ fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser
  }

  /// Folders inside ~/Library that apps keep for themselves and Finder hides.
  static let hiddenAppStorage = [
    "Library/Containers", "Library/Group Containers", "Library/Caches", "Library/Messages",
    "Library/Mail",
  ]

  static func isHiddenAppStorage(_ folder: URL, home: URL) -> Bool {
    let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
    let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
    return hiddenAppStorage.contains { path == "\(homePath)/\($0)" || path.hasPrefix("\(homePath)/\($0)/") }
  }
}

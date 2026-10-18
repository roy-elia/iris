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
  public static func directory(for source: URL, location: OutputLocation) -> URL {
    switch location {
    case .nextToSource: source.deletingLastPathComponent()
    case .folder(let url): url
    }
  }
}

import Foundation

/// File actions that don't create new content: moving, copying paths, finding a folder.
public enum FileActions {
  /// Moves each file into `folder`, renaming on collision. Returns the new locations in
  /// order; files that fail are reported in `failures` and left where they were.
  public static func move(_ files: [URL], to folder: URL, fileManager: FileManager = .default)
    -> (moved: [URL], failures: [OperationResult.Failure])
  {
    var moved: [URL] = []
    var failures: [OperationResult.Failure] = []
    var reserved: Set<URL> = []
    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      return ([], [.init(file: "", message: "\(folder.lastPathComponent) could not be created.")])
    }
    for file in files {
      if file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
        moved.append(file)  // Already there.
        continue
      }
      let target = OutputNamer.uniqueURL(
        for: folder.appendingPathComponent(file.lastPathComponent), reserved: reserved,
        fileManager: fileManager)
      reserved.insert(target.standardizedFileURL)
      do {
        try fileManager.moveItem(at: file, to: target)
        moved.append(target)
      } catch {
        failures.append(.init(file: file.lastPathComponent, message: "could not be moved."))
      }
    }
    return (moved, failures)
  }

  /// Paths one per line, ready to paste into a terminal or document.
  public static func pathText(for files: [URL]) -> String {
    files.map(\.path).joined(separator: "\n")
  }

  /// The deepest folder containing every file, for opening a terminal there.
  public static func commonFolder(of files: [URL]) -> URL? {
    guard let first = files.first else { return nil }
    var components = first.deletingLastPathComponent().standardizedFileURL.pathComponents
    for file in files.dropFirst() {
      let other = file.deletingLastPathComponent().standardizedFileURL.pathComponents
      let shared = zip(components, other).prefix { $0 == $1 }.count
      components = Array(components.prefix(shared))
    }
    guard !components.isEmpty else { return URL(fileURLWithPath: "/") }
    return URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
  }
}

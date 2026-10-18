import Foundation

/// A fresh temporary folder per test, removed when the value goes away.
final class TempDir {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("fdu-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  func file(_ name: String) -> URL { url.appendingPathComponent(name) }

  @discardableResult
  func touch(_ name: String, contents: String = "x") throws -> URL {
    let target = file(name)
    try Data(contents.utf8).write(to: target)
    return target
  }
}

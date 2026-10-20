import Foundation
import Testing

@testable import DropCore

/// Collects what a watcher reports.
private final class Reports: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [(URL, OperationResult)] = []
  func add(_ url: URL, _ result: OperationResult) { lock.withLock { items.append((url, result)) } }
  var all: [(URL, OperationResult)] { lock.withLock { items } }
}

private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool) async -> Bool {
  let end = Date().addingTimeInterval(timeout)
  while Date() < end {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(200))
  }
  return condition()
}

@Suite(.serialized) struct WatchFolderTests {
  private func watcher(_ reports: Reports) -> FolderWatcher {
    let w = FolderWatcher(settings: { AppSettings() }, report: { _, url, result in reports.add(url, result) })
    w.pollInterval = 0.3
    w.settleTime = 0.4
    return w
  }

  @Test func convertsNewFilesIntoConverted() async throws {
    let dir = try TempDir()
    let inbox = dir.file("Inbox")
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    // Already there when watching starts: left alone.
    _ = try Fixtures.writeImage(to: inbox.appendingPathComponent("old.png"), type: "public.png")
    let reports = Reports()
    let w = watcher(reports)
    let folder = WatchFolder(
      path: inbox.path, recipe: Recipe(name: "To JPEG", steps: [.action(.convertImage(.jpeg))]))
    w.update([folder])

    _ = try Fixtures.writeImage(to: inbox.appendingPathComponent("new.png"), type: "public.png")
    let converted = folder.outputURL.appendingPathComponent("new.jpg")
    #expect(await waitUntil { FileManager.default.fileExists(atPath: converted.path) })
    #expect(reports.all.count == 1 && reports.all[0].1.failures.isEmpty)
    // Results in Converted aren't picked up again, and the old file was skipped.
    try await Task.sleep(for: .milliseconds(1500))
    #expect(reports.all.count == 1)
    #expect(!FileManager.default.fileExists(atPath: folder.outputURL.appendingPathComponent("old.jpg").path))
    // The original stays.
    #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent("new.png").path))
    w.stop()
  }

  @Test func movesOriginalsWhenAsked() async throws {
    let dir = try TempDir()
    let inbox = dir.file("Drop")
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let reports = Reports()
    let w = watcher(reports)
    let folder = WatchFolder(
      path: inbox.path, recipe: Recipe(name: "Half", steps: [.action(.resize(.percent(50)))]),
      afterwards: .moveToOriginals)
    w.update([folder])
    _ = try Fixtures.writeImage(to: inbox.appendingPathComponent("photo.png"), type: "public.png")
    #expect(
      await waitUntil {
        FileManager.default.fileExists(atPath: folder.originalsURL.appendingPathComponent("photo.png").path)
      })
    #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent("photo.png").path))
    #expect(reports.all.first?.1.outputs.first?.deletingLastPathComponent().lastPathComponent == "Converted")
    w.stop()
  }

  @Test func ignoresPartialDownloadsAndDisabledFolders() throws {
    let dir = try TempDir()
    let inbox = dir.file("In")
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    try Data([1]).write(to: inbox.appendingPathComponent("movie.mp4.crdownload"))
    try Data([1]).write(to: inbox.appendingPathComponent(".hidden"))
    try FileManager.default.createDirectory(
      at: inbox.appendingPathComponent("Sub"), withIntermediateDirectories: true)
    try Data([1]).write(to: inbox.appendingPathComponent("ok.txt"))
    let folder = WatchFolder(path: inbox.path, recipe: Recipe(name: "x", steps: [.action(.compress)]))
    #expect(FolderWatcher.candidates(in: folder).map(\.lastPathComponent) == ["ok.txt"])
  }

  @Test func watchFoldersPersistInSettings() throws {
    var settings = AppSettings()
    settings.watchFolders = [
      WatchFolder(
        path: "/tmp/In", recipe: Recipe(name: "Subs", steps: [.action(.transcribe)]),
        afterwards: .moveToOriginals)
    ]
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(back.watchFolders == settings.watchFolders)
    let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(old.watchFolders.isEmpty)
  }
}

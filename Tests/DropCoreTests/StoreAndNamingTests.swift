import Foundation
import Testing

@testable import DropCore

@Suite struct OutputNamerTests {
  @Test func keepsFreeName() throws {
    let dir = try TempDir()
    let desired = dir.file("a.png")
    #expect(OutputNamer.uniqueURL(for: desired) == desired)
  }

  @Test func addsCounterOnCollision() throws {
    let dir = try TempDir()
    try dir.touch("a.png")
    try dir.touch("a (1).png")
    #expect(OutputNamer.uniqueURL(for: dir.file("a.png")).lastPathComponent == "a (2).png")
  }

  @Test func respectsReservedPathsAndNoExtension() throws {
    let dir = try TempDir()
    let reserved: Set<URL> = [dir.file("out").standardizedFileURL]
    #expect(OutputNamer.uniqueURL(for: dir.file("out"), reserved: reserved).lastPathComponent == "out (1)")
  }

  @Test func directoryFollowsLocation() {
    let src = URL(fileURLWithPath: "/x/y/photo.png")
    #expect(OutputNamer.directory(for: src, location: .nextToSource).path == "/x/y")
    let folder = URL(fileURLWithPath: "/out")
    #expect(OutputNamer.directory(for: src, location: .folder(folder)) == folder)
  }

  @Test func readOnlyFolderFallsBackToDownloads() throws {
    let dir = try TempDir()
    let locked = dir.file("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
    let downloads = dir.file("Downloads")
    let src = locked.appendingPathComponent("photo.png")

    let nextTo = OutputNamer.resolve(for: src, location: .nextToSource, downloads: downloads)
    #expect(nextTo.url == downloads && nextTo.fellBack)
    let chosen = OutputNamer.resolve(for: src, location: .folder(locked), downloads: downloads)
    #expect(chosen.url == downloads && chosen.fellBack)
  }

  @Test func writableOrMissingFolderIsKept() throws {
    let dir = try TempDir()
    let downloads = dir.file("Downloads")
    let src = dir.file("photo.png")
    let nextTo = OutputNamer.resolve(for: src, location: .nextToSource, downloads: downloads)
    #expect(nextTo.url.standardizedFileURL == dir.url.standardizedFileURL && !nextTo.fellBack)
    // A chosen folder that doesn't exist yet gets created, not replaced.
    let missing = dir.file("not-yet")
    let chosen = OutputNamer.resolve(for: src, location: .folder(missing), downloads: downloads)
    #expect(chosen.url == missing && !chosen.fellBack)
  }

  @Test func hiddenAppStorageCountsAsTemporary() {
    let home = URL(fileURLWithPath: "/Users/me")
    func hidden(_ path: String) -> Bool {
      OutputNamer.isHiddenAppStorage(URL(fileURLWithPath: path), home: home)
    }
    #expect(hidden("/Users/me/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC"))
    #expect(hidden("/Users/me/Library/Messages/Attachments/1a/02"))
    #expect(hidden("/Users/me/Library/Caches/com.example"))
    #expect(!hidden("/Users/me/Documents"))
    #expect(!hidden("/Users/me/Library/Mobile Documents/com~apple~CloudDocs"))
    #expect(!hidden("/Users/me/Library/CachesBackup"))
  }
}

@Suite struct SettingsStoreTests {
  @Test func defaultsWhenMissingOrCorrupt() throws {
    let dir = try TempDir()
    let store = SettingsStore(fileURL: dir.file("sub/settings.json"))
    #expect(store.load() == AppSettings())
    try dir.touch("bad.json", contents: "{not json")
    #expect(SettingsStore(fileURL: dir.file("bad.json")).load() == AppSettings())
  }

  @Test func persistsAcrossInstances() throws {
    let dir = try TempDir()
    let url = dir.file("sub/settings.json")
    let saved = AppSettings(defaultFormat: .tiff, quality: 0.3, launchAtLogin: true)
    try SettingsStore(fileURL: url).save(saved)
    #expect(SettingsStore(fileURL: url).load() == saved)
  }
}

@Suite struct HistoryStoreTests {
  @Test func newestFirstAndCapped() throws {
    let dir = try TempDir()
    let store = HistoryStore(fileURL: dir.file("history.json"), limit: 3)
    for i in 1...5 {
      try store.append(HistoryEntry(operation: "op\(i)", inputCount: 1, outputs: ["o"], errors: []))
    }
    let entries = HistoryStore(fileURL: dir.file("history.json"), limit: 3).load()
    #expect(entries.map(\.operation) == ["op5", "op4", "op3"])
  }

  @Test func defaultLimitIsFifty() throws {
    let dir = try TempDir()
    let store = HistoryStore(fileURL: dir.file("h.json"))
    for i in 0..<60 {
      try store.append(HistoryEntry(operation: "\(i)", inputCount: 1, outputs: [], errors: []))
    }
    #expect(store.load().count == 50)
  }

  @Test func clearEmptiesAndCorruptFileReadsEmpty() throws {
    let dir = try TempDir()
    let store = HistoryStore(fileURL: dir.file("h.json"))
    try store.append(HistoryEntry(operation: "x", inputCount: 1, outputs: [], errors: []))
    try store.clear()
    #expect(store.load().isEmpty)
    try dir.touch("bad.json", contents: "nope")
    #expect(HistoryStore(fileURL: dir.file("bad.json")).load().isEmpty)
  }
}

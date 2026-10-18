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

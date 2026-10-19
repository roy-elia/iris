import Foundation
import Testing

@testable import DropCore

@Suite struct ArchiveTests {
  /// A folder "photos" holding a.txt and sub/b.txt, inside `dir`/src.
  private func source(_ dir: TempDir) throws -> URL {
    let src = dir.file("src")
    try FileManager.default.createDirectory(
      at: src.appendingPathComponent("photos/sub"), withIntermediateDirectories: true)
    try "alpha".write(to: src.appendingPathComponent("photos/a.txt"), atomically: true, encoding: .utf8)
    try "beta".write(to: src.appendingPathComponent("photos/sub/b.txt"), atomically: true, encoding: .utf8)
    return src
  }

  private func extract(_ archive: URL, in dir: TempDir) async throws -> OperationResult {
    await Processor(settings: AppSettings(outputLocation: .folder(dir.file("out"))))
      .run(.extractArchive, on: [try DroppedFile.load(archive)])
  }

  @Test func recognisesArchiveExtensions() async {
    for name in [
      "a.zip", "a.cbz", "a.7z", "a.tar", "a.tar.gz", "a.tgz", "a.tar.bz2", "a.tar.xz", "a.gz", "a.iso",
    ] {
      #expect(FileKind(url: URL(fileURLWithPath: "/\(name)")) == .archive, "\(name)")
    }
    #expect(ArchiveOps.outputName(for: URL(fileURLWithPath: "/x/photos.tar.gz")) == "photos")
    #expect(ArchiveOps.outputName(for: URL(fileURLWithPath: "/x/notes.txt.gz")) == "notes.txt")
    #expect(ArchiveOps.listedSize("-rw-r--r--  0 user staff     1234 Oct 19 01:23 a b.txt") == 1234)
  }

  @Test(arguments: [
    ("photos.7z", ["-c", "--format", "7zip"]), ("photos.tar", ["-c"]), ("photos.tar.gz", ["-cz"]),
    ("photos.tar.bz2", ["-cj"]), ("photos.tar.xz", ["-cJ"]), ("photos.iso", ["-c", "--format", "iso9660"]),
  ])
  func extractsWithBsdtar(name: String, flags: [String]) async throws {
    let dir = try TempDir()
    let src = try source(dir)
    let archive = dir.file(name)
    try await SystemProcess.run("/usr/bin/bsdtar", flags + ["-f", archive.path, "photos"], in: src)
    let result = try await extract(archive, in: dir)
    let folder = try #require(result.outputs.first, "\(result.failures)")
    #expect(folder.lastPathComponent == "photos")
    // ISO 9660 names come back in upper case; compare without case.
    let text = try FileManager.default.subpathsOfDirectory(atPath: folder.path).map { $0.lowercased() }
    #expect(text.contains("photos/sub/b.txt"), "\(text)")
  }

  @Test(arguments: [("notes.txt.gz", "-z"), ("notes.txt.bz2", "-j"), ("notes.txt.xz", "-J")])
  func decompressesSingleFiles(name: String, flag: String) async throws {
    let dir = try TempDir()
    let src = try source(dir)
    let archive = dir.file(name)
    try await SystemProcess.run(
      "/usr/bin/bsdtar", ["-c", "--format", "raw", flag, "-f", archive.path, "photos/a.txt"], in: src)
    let out = try #require(try await extract(archive, in: dir).outputs.first)
    #expect(out.lastPathComponent == "notes.txt")
    #expect(try String(contentsOf: out, encoding: .utf8) == "alpha")
  }

  @Test func refusesEntriesThatEscape() async throws {
    let dir = try TempDir()
    let src = try source(dir)
    let archive = dir.file("evil.tar")
    // -P keeps the "../" in the stored name.
    try await SystemProcess.run(
      "/usr/bin/bsdtar", ["-c", "-P", "-f", archive.path, "photos/../photos/a.txt"], in: src)
    let result = try await extract(archive, in: dir)
    #expect(result.outputs.isEmpty)
    #expect(result.failures.first?.message.contains("outside its folder") == true)
    #expect(!FileManager.default.fileExists(atPath: dir.file("out/evil").path))
  }

  @Test func refusesNonArchives() async throws {
    let dir = try TempDir()
    let fake = try dir.touch("fake.7z", contents: "not an archive")
    let result = try await extract(fake, in: dir)
    #expect(result.failures.first?.message.contains("isn't an archive") == true)
  }

  @Test func zipsAnyFilesIntoOneArchive() async throws {
    let dir = try TempDir()
    let src = try source(dir)
    let other = try dir.touch("readme.xyz", contents: "anything")
    let items = [src.appendingPathComponent("photos"), other].map {
      DroppedFile(url: $0, kind: FileKind(url: $0), byteSize: 0)
    }
    let result = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.zipFiles, on: items)
    let zip = try #require(result.outputs.first, "\(result.failures)")
    #expect(zip.lastPathComponent == "Archive.zip")
    let names = String(
      decoding: try await SystemProcess.run("/usr/bin/zipinfo", ["-1", zip.path]).stdout, as: UTF8.self)
    #expect(names.contains("photos/sub/b.txt") && names.contains("readme.xyz"), "\(names)")
    #expect(!names.contains("__MACOSX"))

    let single = await Processor(settings: AppSettings(outputLocation: .folder(dir.url)))
      .run(.zipFiles, on: [items[1]])
    #expect(single.outputs.first?.lastPathComponent == "readme.xyz.zip")
  }
}

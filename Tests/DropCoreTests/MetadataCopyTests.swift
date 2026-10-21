import Foundation
import ImageIO
import Testing

@testable import DropCore

private func load(_ urls: URL...) throws -> [DroppedFile] { try urls.map { try DroppedFile.load($0) } }

/// ExifTool's full listing (`-a -G1 -s -n`), one "[Group] Tag : value" line each.
private func listing(_ url: URL) async throws -> [String] {
  let out = try await ToolRunner.run(.exiftool, ["-a", "-G1", "-s", "-n", url.path])
  return String(decoding: out.stdout, as: UTF8.self).split(separator: "\n").map(String.init)
}

/// Writes rich metadata into `url` in place: EXIF, maker info, GPS, IPTC, XMP, a comment,
/// an orientation and a colour profile.
private func plantMetadata(in url: URL, profile: String = "Display P3") async throws {
  _ = try await ToolRunner.run(
    .exiftool,
    [
      "-q", "-overwrite_original", "-Artist=Alice", "-Make=Canon", "-Model=EOS R5", "-Software=SourceApp",
      "-DateTimeOriginal=2020:01:02 03:04:05", "-GPSLatitude=45.5", "-GPSLatitudeRef=N",
      "-GPSLongitude=73.6", "-GPSLongitudeRef=W", "-XMP-dc:Title=Source title", "-IPTC:Keywords=one",
      "-IPTC:Keywords=two", "-Comment=source comment", "-Orientation#=6",
      "-ICC_Profile<=/System/Library/ColorSync/Profiles/\(profile).icc", url.path,
    ])
}

@Suite struct CompleteStripTests {
  /// Every format the metadata tool takes comes out with nothing but what a decoder needs.
  @Test(
    .enabled(if: ToolLocator.isAvailable(.exiftool)),
    arguments: [
      ("jpg", "public.jpeg"), ("png", "public.png"), ("heic", "public.heic"), ("tiff", "public.tiff"),
      ("gif", "com.compuserve.gif"), ("jp2", "public.jpeg-2000"), ("avif", "public.avif"),
    ])
  func leavesNoMetadata(ext: String, type: String) async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("m.\(ext)"), type: type, withMetadata: true)
    // ExifTool can't write GIF or AVIF metadata; macOS can't decode JPEG 2000 with a P3 profile.
    if ext != "gif" && ext != "avif" {
      try await plantMetadata(in: src, profile: ext == "jp2" ? "sRGB Profile" : "Display P3")
    }
    _ = setxattr(src.path, "com.example.tag", "x", 1, 0, 0)

    let result = await Processor(settings: AppSettings()).run(.stripAllMetadata, on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let lines = try await listing(out)
    let metadataGroups = [
      "[IFD1]", "[ExifIFD]", "[GPS]", "[IPTC]", "[XMP", "[ICC", "[JFIF]", "[Photoshop]", "[MakerNotes",
      "[Canon", "[InteropIFD]",
    ]
    let left = lines.filter { line in
      metadataGroups.contains { line.hasPrefix($0) }
        || ["TestCam", "Someone", "secret comment", "Alice", "Canon", "Source title", "source comment"]
          .contains { line.contains($0) }
    }
    #expect(left.isEmpty, "left behind in .\(ext): \(left)")
    #expect(MetadataOps.extendedAttributeNames(of: out).isEmpty)
  }
}

@Suite(.enabled(if: ToolLocator.isAvailable(.exiftool))) struct MetadataCopyTests {
  /// Lines that describe the file rather than its metadata, or that ExifTool can't write.
  private func comparable(_ lines: [String]) -> Set<String> {
    let skipped = ["[System]", "[ExifTool]", "[File]", "[Composite]"]
    return Set(
      lines.filter { line in
        !skipped.contains { line.hasPrefix($0) } && !line.contains("JFIFVersion")
      })
  }

  @Test func sameFormatCopyIsExact() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("src.jpg"), withMetadata: true)
    try await plantMetadata(in: src)
    let target = try Fixtures.writeImage(to: dir.file("target.jpg"), width: 80, height: 60)
    _ = try await ToolRunner.run(
      .exiftool, ["-q", "-overwrite_original", "-Software=TargetApp", "-XMP-dc:Creator=Bob", target.path])

    // File attributes: a Finder tag, the target's own attribute, and old dates.
    let tags = try PropertyListSerialization.data(fromPropertyList: ["Red\n6"], format: .binary, options: 0)
    _ = tags.withUnsafeBytes {
      setxattr(src.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, tags.count, 0, 0)
    }
    _ = setxattr(target.path, "com.example.target-only", "x", 1, 0, 0)
    let created = Date(timeIntervalSince1970: 1_000_000_000)
    let modified = Date(timeIntervalSince1970: 1_100_000_000)
    try FileManager.default.setAttributes(
      [.creationDate: created, .modificationDate: modified, .posixPermissions: 0o640], ofItemAtPath: src.path)

    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(out.lastPathComponent == "target metadata.jpg")

    let expected = comparable(try await listing(src))
    let actual = comparable(try await listing(out))
    #expect(expected.subtracting(actual).isEmpty, "missing: \(expected.subtracting(actual).sorted())")
    #expect(actual.subtracting(expected).isEmpty, "extra: \(actual.subtracting(expected).sorted())")
    #expect(!actual.contains { $0.contains("TargetApp") || $0.contains("Bob") })
    // The pixels are still the target's.
    #expect(Fixtures.properties(of: out)[kCGImagePropertyPixelWidth] as? Int == 80)

    #expect(MetadataOps.extendedAttributeNames(of: out) == ["com.apple.metadata:_kMDItemUserTags"])
    let attributes = try FileManager.default.attributesOfItem(atPath: out.path)
    #expect(attributes[.creationDate] as? Date == created)
    #expect(attributes[.modificationDate] as? Date == modified)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
    // The target itself is untouched.
    #expect(try await listing(target).contains { $0.contains("TargetApp") })
  }

  @Test func copiesIntoAnotherFormat() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("src.jpg"), withMetadata: true)
    try await plantMetadata(in: src)
    let target = try Fixtures.writeImage(to: dir.file("target.png"), type: "public.png")
    _ = try await ToolRunner.run(
      .exiftool, ["-q", "-overwrite_original", "-XMP-dc:Creator=Bob", target.path])

    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let fields = try await MetadataOps.read(out)
    for (field, value) in [(2, "Alice"), (0, "Source title")] {
      #expect(MetadataOps.value(of: EditableField.all[field], in: fields) == value)
    }
    #expect(fields.contains { $0.group == "GPS" })
    #expect(fields.contains { $0.group.hasPrefix("ICC") })
    #expect(!fields.contains { $0.value == "Bob" })
  }

  @Test func refusesACopyThatWouldLeaveTheImageUnreadable() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writeImage(to: dir.file("src.jpg"))
    try await plantMetadata(in: src)
    let target = try Fixtures.writeImage(to: dir.file("target.jp2"), type: "public.jpeg-2000")

    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    #expect(result.outputs.isEmpty)
    #expect(result.failures.first?.message.contains("would leave target.jp2 unreadable") == true)
    #expect(!FileManager.default.fileExists(atPath: dir.file("target metadata.jp2").path))
  }

  @Test func refusesFilesThatCantHoldMetadataAndMissingSources() throws {
    let dir = try TempDir()
    let image = try load(Fixtures.writeImage(to: dir.file("a.jpg")))
    #expect(
      Processor.validate(.copyMetadata(from: dir.file("gone.jpg").path), files: image)
        == "The file to copy metadata from is no longer there.")
    let bmp = try load(Fixtures.writeImage(to: dir.file("b.bmp"), type: "com.microsoft.bmp"))
    #expect(
      Processor.validate(.copyMetadata(from: image[0].url.path), files: bmp)
        == "b.bmp can't hold photo metadata. Convert it to JPEG, PNG or TIFF first.")
  }
}

/// Audio, video and PDFs: strip leaves no tags, and copy carries the source's over.
@Suite(.enabled(if: ToolLocator.isAvailable(.ffmpeg) && ToolLocator.isAvailable(.exiftool)))
struct MediaAndPDFMetadataTests {
  private let secrets = ["SecretTitle", "Alice", "secretcomment", "AlbumX", "45.5"]

  /// Writes a one-second file tagged with `secrets`; audio files get cover art too.
  private func makeMedia(_ url: URL) async throws -> URL {
    let isVideo = FileKind(url: url).isVideo
    var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error"]
    if isVideo { args += ["-f", "lavfi", "-i", "testsrc=d=1:s=64x48"] }
    args += ["-f", "lavfi", "-i", "sine=d=1"]
    let cover = url.deletingLastPathComponent().appendingPathComponent("cover.png")
    if !isVideo, url.pathExtension != "m4a" {
      _ = try Fixtures.writeImage(to: cover, type: "public.png")
      args += ["-i", cover.path, "-map", "0", "-map", "1", "-disposition:v", "attached_pic"]
    }
    args += [
      "-metadata", "title=SecretTitle", "-metadata", "artist=Alice", "-metadata", "comment=secretcomment",
      "-metadata", "album=AlbumX", "-metadata", "location=+45.5-073.6/", "-shortest",
    ]
    switch url.pathExtension {
    case "mp4", "mov": args += ["-c:v", "mpeg4", "-c:a", "aac"]
    case "mkv": args += ["-c:v", "mpeg4", "-c:a", "flac"]
    case "mp3": args += ["-c:a", "libmp3lame", "-c:v", "png", "-id3v2_version", "3"]
    case "flac": args += ["-c:a", "flac", "-c:v", "png"]
    default: args += ["-c:a", "aac"]
    }
    _ = try await ToolRunner.run(.ffmpeg, args + [url.path])
    return url
  }

  /// Every tag ExifTool and ffprobe can see, as text.
  private func everything(_ url: URL) async throws -> String {
    let exif = try await ToolRunner.run(.exiftool, ["-a", "-G1", "-s", "-ee", url.path]).stdout
    let probe = try await ToolRunner.run(
      .ffprobe, ["-v", "error", "-show_entries", "format_tags:stream_tags:stream=codec_type", url.path]
    ).stdout
    return String(decoding: exif + probe, as: UTF8.self)
  }

  @Test(arguments: ["mp4", "mov", "mkv", "mp3", "m4a", "flac"])
  func stripLeavesNoTagsOrCoverArt(ext: String) async throws {
    let dir = try TempDir()
    let src = try await makeMedia(dir.file("in.\(ext)"))
    #expect(try await everything(src).contains("SecretTitle"))
    let result = await Processor(settings: AppSettings()).run(.stripAllMetadata, on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let left = try await everything(out)
    for secret in secrets { #expect(!left.contains(secret), "\(secret) left in .\(ext)") }
    // Matroska requires a writing-app field; ffmpeg fills it with a bare "Lavf".
    if ext != "mkv" { #expect(!left.contains("Lavf"), "ffmpeg named itself in .\(ext)") }
    if ext == "mp3" || ext == "flac" { #expect(!left.contains("codec_type=video"), "cover art left") }
  }

  @Test(arguments: [("mp3", "flac"), ("mp4", "mp4"), ("mp4", "mkv"), ("m4a", "mp3")])
  func copyCarriesTagsAcross(source ext: String, target targetExt: String) async throws {
    let dir = try TempDir()
    let src = try await makeMedia(dir.file("src.\(ext)"))
    let plain = try await makeMedia(dir.file("plain.\(targetExt)"))
    let target = dir.file("target.\(targetExt)")
    _ = try await ToolRunner.run(
      .ffmpeg,
      ["-v", "error", "-i", plain.path, "-map", "0", "-c", "copy", "-map_metadata", "-1"]
        + ["-metadata", "title=TargetOnly", target.path])

    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    let out = try #require(result.outputs.first, "\(result.failures)")
    let tags = try await everything(out)
    for secret in ["SecretTitle", "Alice", "AlbumX"] { #expect(tags.contains(secret), "\(secret) missing") }
    #expect(!tags.contains("TargetOnly"))
  }

  @Test func pdfStripLeavesNothingRecoverable() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writePDF(to: dir.file("in.pdf"), pages: 2)
    _ = try await ToolRunner.run(
      .exiftool,
      ["-q", "-overwrite_original", "-Title=SecretTitle", "-Author=Alice", "-XMP-dc:Creator=Alice", src.path])

    let result = await Processor(settings: AppSettings()).run(.stripAllMetadata, on: try load(src))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(PDFOps.pageCount(of: out) == 2)
    // Not even an earlier revision holds the values, nor does Quartz's info block.
    let bytes = String(decoding: try Data(contentsOf: out), as: UTF8.self)
    for secret in ["SecretTitle", "Alice", "Producer", "CreationDate", "Quartz"] {
      #expect(!bytes.contains(secret), "\(secret) still in the PDF")
    }
    let left = try await MetadataOps.read(out).map(\.id)
    let structural: Set = ["PDF:PDFVersion", "PDF:Linearized", "PDF:PageCount", "PDF:MediaBox"]
    #expect(Set(left).isSubset(of: structural), "\(left)")
  }

  @Test func pdfCopyReplacesInfo() async throws {
    let dir = try TempDir()
    let src = try Fixtures.writePDF(to: dir.file("src.pdf"), pages: 1)
    _ = try await ToolRunner.run(
      .exiftool, ["-q", "-overwrite_original", "-Title=SecretTitle", "-Author=Alice", src.path])
    let target = try Fixtures.writePDF(to: dir.file("target.pdf"), pages: 3)
    _ = try await ToolRunner.run(.exiftool, ["-q", "-overwrite_original", "-Author=TargetOnly", target.path])

    let result = await Processor(settings: AppSettings())
      .run(.copyMetadata(from: src.path), on: try load(target))
    let out = try #require(result.outputs.first, "\(result.failures)")
    #expect(PDFOps.pageCount(of: out) == 3)
    let fields = try await MetadataOps.read(out)
    #expect(fields.contains { $0.tag == "Title" && $0.value == "SecretTitle" })
    #expect(fields.contains { $0.tag == "Author" && $0.value == "Alice" })
    // The target's own author isn't recoverable from an earlier revision either.
    #expect(!String(decoding: try Data(contentsOf: out), as: UTF8.self).contains("TargetOnly"))
  }

  @Test func unsupportedFilesAreRefused() throws {
    let dir = try TempDir()
    let text = try load(dir.touch("notes.txt", contents: "hi"))
    #expect(Processor.validate(.stripAllMetadata, files: text)?.contains("isn't supported") == true)
    #expect(
      Processor.validate(.copyMetadata(from: text[0].url.path), files: text)?.contains("isn't supported")
        == true)
  }
}

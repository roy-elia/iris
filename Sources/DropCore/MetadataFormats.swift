import Foundation
import PDFKit

/// How the metadata tools treat each kind of file: images go through ExifTool and ImageIO,
/// audio and video are remuxed by ffmpeg (streams are copied, never re-encoded), and PDFs
/// are rewritten by PDFKit so deleted values can't be recovered from earlier revisions.
/// Word, Excel and PowerPoint files are zip packages whose parts are rewritten directly.
public enum MetadataSupport: Equatable, Sendable {
  case image, media, pdf, office

  public init?(_ kind: FileKind) {
    switch kind {
    case .image(let format) where format.supportsMetadataEditing: self = .image
    case .pdf: self = .pdf
    // The zip-based formats. The older binary .doc, .xls and .ppt aren't supported.
    case .document(.docx), .office(.xlsx), .office(.pptx): self = .office
    // ffmpeg reads Monkey's Audio and DVD VOB files but can't write them.
    case .audio(.ape), .video(.vob): return nil
    case .audio, .video: self = .media
    default: return nil
    }
  }

  /// MP4, MOV, M4A and 3GP: ExifTool writes their metadata directly.
  static func isQuickTime(_ url: URL) -> Bool {
    ["mp4", "mov", "m4v", "m4a", "3gp"].contains(url.pathExtension.lowercased())
  }
}

extension MetadataOps {
  // MARK: Audio and video

  /// Writes a copy of `source` with no tags, chapters, cover art or data tracks (such as
  /// location tracks). Streams are copied as they are; `bitexact` stops ffmpeg naming itself.
  public static func stripMedia(_ source: URL, destination: URL) async throws {
    try await runFFmpeg(
      ["-i", source.path, "-map", "0", "-map", "-0:disp:attached_pic", "-dn"]
        + ["-map_metadata", "-1", "-map_chapters", "-1"] + bitexact + [destination.path],
      destination: destination)
    removeExtendedAttributes(from: destination)
  }

  /// Writes a copy of `target`'s audio and video with `source`'s tags, chapters, per-stream
  /// tags and cover art in place of its own.
  static func copyMedia(from source: URL, onto target: URL, destination: URL) async throws {
    // Per-stream tags go across only for stream types both files have; ffmpeg refuses a
    // mapping that matches nothing.
    let shared = try await streamTypes(of: target).intersection(try await streamTypes(of: source))
    let streamTags = ["v", "a", "s"].filter(shared.contains).flatMap {
      ["-map_metadata:s:\($0)", "1:s:\($0)"]
    }
    try await runFFmpeg(
      ["-i", target.path, "-i", source.path, "-map", "0", "-map", "-0:disp:attached_pic", "-dn"]
        + ["-map", "1:disp:attached_pic?", "-map_metadata", "1", "-map_chapters", "1"] + streamTags
        + ["-movflags", "use_metadata_tags"] + bitexact + [destination.path],
      destination: destination)
  }

  /// "v", "a" and "s" for the video, audio and subtitle streams in `url`, cover art aside.
  static func streamTypes(of url: URL) async throws -> Set<String> {
    let output = try await ToolRunner.run(
      .ffprobe,
      [
        "-v", "error", "-show_entries", "stream=codec_type:stream_disposition=attached_pic", "-of", "csv=p=0",
        url.path,
      ])
    return Set(
      String(decoding: output.stdout, as: UTF8.self).split(separator: "\n").compactMap { line in
        let parts = line.split(separator: ",")
        guard parts.count == 2, parts[1] == "0" else { return nil }
        return ["video": "v", "audio": "a", "subtitle": "s"][String(parts[0])]
      })
  }

  private static let bitexact = [
    "-c", "copy", "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
  ]

  private static func runFFmpeg(_ args: [String], destination: URL) async throws {
    do {
      _ = try await ToolRunner.run(.ffmpeg, ["-hide_banner", "-nostdin", "-y", "-loglevel", "error"] + args)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  // MARK: PDF

  /// Writes a copy of `source` with no document info, XMP or file attributes. ExifTool's
  /// PDF edits only append a revision, so PDFKit then rewrites the file without the old
  /// ones, and the info Quartz adds (macOS build, dates) and the file ID are blanked.
  public static func stripPDF(_ source: URL, destination: URL) async throws {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("fdu-pdf-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: scratch) }
    do {
      if ToolLocator.isAvailable(.exiftool) {
        _ = try await ToolRunner.run(.exiftool, ["-q", "-m", "-all=", "-o", scratch.path, source.path])
      } else {
        try FileManager.default.copyItem(at: source, to: scratch)
      }
      guard let document = PDFDocument(url: scratch) else {
        throw DropError.readFailed(source.lastPathComponent)
      }
      if document.isEncrypted {
        throw DropError.wrongInput("\(source.lastPathComponent) is password-protected. Unlock it first.")
      }
      document.documentAttributes = [:]
      guard document.write(to: destination) else {
        throw DropError.writeFailed(destination.lastPathComponent)
      }
      try blankQuartzInfo(in: destination)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  /// Overwrites the trailer's info dictionary and file ID with spaces and zeros of the same
  /// length, so every cross-reference offset stays valid.
  static func blankQuartzInfo(in url: URL) throws {
    var data = try Data(contentsOf: url)
    // Streams hold binary data, so search bytes rather than text.
    func find(_ text: String, in range: Range<Int>, backwards: Bool = false) -> Range<Int>? {
      data.range(of: Data(text.utf8), options: backwards ? .backwards : [], in: range)
    }
    func blank(_ range: Range<Int>, with fill: (UInt8) -> UInt8) {
      for i in range { data[i] = fill(data[i]) }
    }
    guard let trailer = find("trailer", in: 0..<data.count, backwards: true) else { return }
    let tail = String(decoding: data[trailer.lowerBound...], as: UTF8.self)
    // "/Info 9 0 R" → the "9 0 obj << … >>" it points at becomes "<<" spaces ">>".
    if let info = tail.firstMatch(of: /\/Info (\d+) 0 R/),
      let object = find("\n\(info.1) 0 obj", in: 0..<trailer.lowerBound),
      let open = find("<<", in: object.upperBound..<trailer.lowerBound),
      let close = find(">>\nendobj", in: open.upperBound..<trailer.lowerBound)
    {
      blank(open.upperBound..<close.lowerBound) { _ in UInt8(ascii: " ") }
    }
    if let id = find("/ID [", in: trailer.lowerBound..<data.count),
      let end = find("]", in: id.upperBound..<data.count)
    {
      blank(id.upperBound..<end.lowerBound) { byte in
        let isHex =
          (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
          || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        return isHex ? UInt8(ascii: "0") : byte
      }
    }
    try data.write(to: url)
  }
}

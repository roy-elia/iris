import Foundation
import ImageIO

/// One metadata value, as ExifTool names it ("EXIF:Artist" → group "EXIF", tag "Artist").
public struct MetadataField: Equatable, Hashable, Sendable, Identifiable {
  public let group: String
  public let tag: String
  public let value: String

  public var id: String { "\(group):\(tag)" }

  public init(group: String, tag: String, value: String) {
    self.group = group
    self.tag = tag
    self.value = value
  }
}

/// A change to one tag: a new value, or nil to remove it. `tag` is group-qualified
/// ("XMP-dc:Title"); "GPS:all" with nil removes all location data.
public struct MetadataEdit: Codable, Equatable, Hashable, Sendable {
  public var tag: String
  public var value: String?

  public init(tag: String, value: String?) {
    self.tag = tag
    self.value = value
  }

  /// Removes every GPS tag.
  public static let removeLocation = MetadataEdit(tag: "GPS:all", value: nil)
}

/// The fields the metadata editor offers, with the tag each one writes.
public struct EditableField: Sendable, Identifiable {
  public let label: String
  public let tag: String
  /// Other tags that hold the same information and are read as fallbacks.
  public let alternatives: [String]
  public var id: String { tag }

  public static let all: [EditableField] = [
    .init(label: "Title", tag: "XMP-dc:Title", alternatives: ["IPTC:ObjectName"]),
    .init(
      label: "Description", tag: "EXIF:ImageDescription",
      alternatives: ["XMP-dc:Description", "IPTC:Caption-Abstract"]),
    .init(label: "Artist", tag: "EXIF:Artist", alternatives: ["XMP-dc:Creator", "IPTC:By-line"]),
    .init(
      label: "Copyright", tag: "EXIF:Copyright", alternatives: ["XMP-dc:Rights", "IPTC:CopyrightNotice"]),
    .init(label: "Keywords", tag: "XMP-dc:Subject", alternatives: ["IPTC:Keywords"]),
    .init(label: "Date taken", tag: "EXIF:DateTimeOriginal", alternatives: ["XMP-exif:DateTimeOriginal"]),
  ]
}

/// Reads and writes metadata with the bundled ExifTool, falling back to ImageIO for
/// reading when ExifTool isn't available.
public enum MetadataOps {
  /// Every readable field, sorted by group then tag. File-system and ExifTool's own
  /// bookkeeping fields are left out.
  public static func read(_ url: URL) async throws -> [MetadataField] {
    guard ToolLocator.isAvailable(.exiftool) else {
      return try ImageOps.metadata(of: url).map { key, value in
        let parts = key.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2
          ? MetadataField(group: parts[0], tag: parts[1], value: value)
          : MetadataField(group: "Image", tag: key, value: value)
      }.sorted { ($0.group, $0.tag) < ($1.group, $1.tag) }
    }
    let output = try await ToolRunner.run(
      .exiftool, ["-j", "-G1", "-s", "-struct", "-api", "LargeFileSupport=1", url.path])
    guard
      let array = try JSONSerialization.jsonObject(with: output.stdout) as? [[String: Any]],
      let dict = array.first
    else { throw DropError.readFailed(url.lastPathComponent) }
    let hiddenGroups: Set<String> = ["ExifTool", "System", "File"]
    return dict.compactMap { key, value -> MetadataField? in
      let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count == 2, !hiddenGroups.contains(parts[0]) else { return nil }
      return MetadataField(group: parts[0], tag: parts[1], value: describe(value))
    }.sorted { ($0.group, $0.tag) < ($1.group, $1.tag) }
  }

  /// The current value for an editable field: its own tag, else the first alternative.
  public static func value(of field: EditableField, in fields: [MetadataField]) -> String? {
    for tag in [field.tag] + field.alternatives {
      let parts = tag.split(separator: ":", maxSplits: 1).map(String.init)
      if let match = fields.first(where: { groupMatches(parts[0], $0.group) && $0.tag == parts[1] }) {
        return match.value
      }
    }
    return nil
  }

  /// Reading uses ExifTool's specific groups (`IFD0`, `ExifIFD`); writing uses the
  /// general `EXIF` group, which covers them all.
  static func groupMatches(_ wanted: String, _ actual: String) -> Bool {
    if wanted == actual { return true }
    return wanted == "EXIF" && ["IFD0", "IFD1", "ExifIFD", "SubIFD"].contains(actual)
  }

  /// Writes a copy of `source` with `edits` applied. The original is never touched.
  public static func write(_ source: URL, edits: [MetadataEdit], destination: URL) async throws {
    guard !edits.isEmpty else { throw DropError.wrongInput("There are no metadata changes to save.") }
    guard ToolLocator.isAvailable(.exiftool) else { throw ToolError.missing(.exiftool) }
    var args = ["-q", "-m", "-charset", "UTF8", "-sep", ", "]
    for edit in edits {
      if let value = edit.value, !value.isEmpty {
        args.append("-\(edit.tag)=\(value)")
      } else {
        args.append("-\(edit.tag)=")
      }
    }
    args += ["-o", destination.path, source.path]
    do {
      _ = try await ToolRunner.run(.exiftool, args)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    guard FileManager.default.fileExists(atPath: destination.path) else {
      throw DropError.writeFailed(destination.lastPathComponent)
    }
  }

  /// Copies all metadata from `source` onto `destination` in place (used after encoders
  /// that drop it, like cwebp). Orientation is reset, since pixels were already rotated.
  public static func copyAll(from source: URL, to destination: URL) async throws {
    guard ToolLocator.isAvailable(.exiftool) else { return }
    _ = try await ToolRunner.run(
      .exiftool,
      [
        "-q", "-m", "-overwrite_original", "-tagsFromFile", source.path, "-all:all", "-Orientation=",
        destination.path,
      ])
  }

  /// Removes whatever metadata ImageIO left behind (ICC profile, JFIF, PNG text chunks,
  /// MakerNotes) in place with ExifTool, then the file's extended attributes, such as
  /// quarantine flags and download sources.
  public static func removeEverything(from url: URL) async throws {
    if ToolLocator.isAvailable(.exiftool) {
      _ = try await ToolRunner.run(.exiftool, ["-q", "-m", "-all=", "-overwrite_original", url.path])
    }
    removeExtendedAttributes(from: url)
  }

  /// Writes a copy of `target` whose metadata is an exact copy of `source`'s. The target's
  /// own metadata goes first, so none of it survives; then every tag ExifTool can write is
  /// copied (maker notes, colour profile, thumbnails and orientation included), then the
  /// file's extended attributes (Finder tags, comments, download source), permissions and
  /// created and modified dates. Tags the target's format has no place for are skipped.
  public static func copyExact(from source: URL, onto target: URL, destination: URL) async throws {
    let support = MetadataSupport(FileKind(url: target))
    do {
      switch support {
      case .media where !(MetadataSupport.isQuickTime(target) && MetadataSupport.isQuickTime(source)):
        try await copyMedia(from: source, onto: target, destination: destination)
      case .pdf:
        // Start from a clean rewrite, so the target's old info can't be recovered.
        let clean = FileManager.default.temporaryDirectory
          .appendingPathComponent("fdu-pdf-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: clean) }
        try await stripPDF(target, destination: clean)
        try await copyTags(from: source, onto: clean, destination: destination)
      case .office:
        try await copyOffice(from: source, onto: target, destination: destination)
      default:
        try await copyTags(from: source, onto: target, destination: destination)
      }
      guard FileManager.default.fileExists(atPath: destination.path) else {
        throw DropError.writeFailed(destination.lastPathComponent)
      }
      // Some combinations decode nowhere, such as a Display P3 profile in a JPEG 2000 file.
      if support == .image, decodes(target), !decodes(destination) {
        throw DropError.wrongInput(
          "\(source.lastPathComponent)’s metadata, likely its color profile, would leave "
            + "\(target.lastPathComponent) unreadable, so it wasn’t copied.")
      }
      try copyFileAttributes(from: source, to: destination)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  /// ExifTool's copy: the target's tags removed, then every writable tag of the source's.
  private static func copyTags(from source: URL, onto target: URL, destination: URL) async throws {
    guard ToolLocator.isAvailable(.exiftool) else { throw ToolError.missing(.exiftool) }
    // NoMandatory stops ExifTool adding tags of its own (resolution, EXIF version) that
    // the source doesn't have.
    _ = try await ToolRunner.run(
      .exiftool,
      [
        "-q", "-m", "-api", "NoMandatory=1", "-api", "LargeFileSupport=1", "-all=",
        // IPTCDigest is kept current by ExifTool and only copied when named.
        "-tagsFromFile", source.path, "-all:all", "-unsafe", "-icc_profile", "-Photoshop:IPTCDigest",
        "-o", destination.path, target.path,
      ])
  }

  /// Gives `destination` the extended attributes, permissions and dates of `source`. Dates
  /// go last, since every other change updates the modified date.
  static func copyFileAttributes(from source: URL, to destination: URL) throws {
    removeExtendedAttributes(from: destination)
    for name in extendedAttributeNames(of: source) {
      let size = getxattr(source.path, name, nil, 0, 0, XATTR_NOFOLLOW)
      guard size >= 0 else { continue }
      var value = [UInt8](repeating: 0, count: size)
      guard getxattr(source.path, name, &value, size, 0, XATTR_NOFOLLOW) == size else { continue }
      // Ones macOS manages itself, like com.apple.provenance, refuse to be set.
      _ = setxattr(destination.path, name, value, size, 0, XATTR_NOFOLLOW)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
    var copied: [FileAttributeKey: Any] = [:]
    for key in [FileAttributeKey.posixPermissions, .creationDate, .modificationDate] {
      copied[key] = attributes[key]
    }
    try FileManager.default.setAttributes(copied, ofItemAtPath: destination.path)
  }

  private static func decodes(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return false }
    return properties[kCGImagePropertyPixelWidth] != nil
  }

  static func removeExtendedAttributes(from url: URL) {
    for name in extendedAttributeNames(of: url) {
      _ = removexattr(url.path, name, XATTR_NOFOLLOW)
    }
  }

  static func extendedAttributeNames(of url: URL) -> [String] {
    let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
    guard size > 0 else { return [] }
    var names = [CChar](repeating: 0, count: size)
    guard listxattr(url.path, &names, size, XATTR_NOFOLLOW) == size else { return [] }
    return names.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
  }

  private static func describe(_ value: Any) -> String {
    switch value {
    case let s as String: s
    case let n as NSNumber: n.stringValue
    case let a as [Any]: a.map(describe).joined(separator: ", ")
    case let d as [String: Any]:
      d.sorted { $0.key < $1.key }.map { "\($0.key): \(describe($0.value))" }.joined(separator: "; ")
    default: String(describing: value)
    }
  }
}
